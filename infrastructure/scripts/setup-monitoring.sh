#!/bin/bash
# infrastructure/scripts/setup-monitoring.sh
#
# Устанавливает kube-prometheus-stack (Prometheus + Grafana + Alertmanager +
# node-exporter + kube-state-metrics) в кластер через Helm.
#
# Grafana доступна через ingress-nginx по адресу http://<EXTERNAL-IP>/monitoring.
# ingress-nginx должен быть установлен заранее (setup-ingress-nginx.sh).
#
# Использование:
#   ./scripts/setup-monitoring.sh staging
#
# Переменные окружения (обязательные):
#   GRAFANA_ADMIN_PASSWORD  — пароль admin в Grafana
#   GRAFANA_SMTP_EMAIL      — Gmail-адрес (используется как SMTP user и from_address)
#   GRAFANA_SMTP_PASSWORD   — App Password от Gmail (16 символов)
#
# Переменные окружения (опциональные):
#   MONITORING_NAMESPACE    — namespace (по умолчанию monitoring)
#   KUBE_PROM_STACK_VERSION — версия chart (по умолчанию 65.5.1)

set -e

ENV=${1:-staging}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
RELEASE_NAME="monitoring"
KUBE_PROM_STACK_VERSION="${KUBE_PROM_STACK_VERSION:-65.5.1}"
SMTP_SECRET_NAME="grafana-smtp-secret"

echo "🔧 Setting up monitoring (kube-prometheus-stack) for environment: $ENV"

# ============================================================================
# Проверка переменных
# ============================================================================

if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
    echo "❌ GRAFANA_ADMIN_PASSWORD не задан"
    echo "   Экспортируйте: export GRAFANA_ADMIN_PASSWORD=<strong-password>"
    exit 1
fi

if [ -z "$GRAFANA_SMTP_EMAIL" ]; then
    echo "❌ GRAFANA_SMTP_EMAIL не задан"
    echo "   Экспортируйте: export GRAFANA_SMTP_EMAIL=<your-email@gmail.com>"
    exit 1
fi

if [ -z "$GRAFANA_SMTP_PASSWORD" ]; then
    echo "❌ GRAFANA_SMTP_PASSWORD не задан (App Password от Gmail)"
    echo "   Экспортируйте: export GRAFANA_SMTP_PASSWORD=<app-password>"
    exit 1
fi

# ============================================================================
# 1. Получаем admin kubeconfig
# ============================================================================

echo "==> Fetching admin kubeconfig for $ENV"

yc managed-kubernetes cluster get-credentials \
    --name "${ENV}-managed-k8s" \
    --external \
    --force \
    --kubeconfig /tmp/kubeconfig-admin

export KUBECONFIG=/tmp/kubeconfig-admin

if ! kubectl get nodes > /dev/null 2>&1; then
    echo "❌ Kubeconfig не работает. Проверьте доступ к кластеру ${ENV}-managed-k8s"
    exit 1
fi

echo "✅ Kubeconfig works"

# ============================================================================
# 2. Проверяем, что ingress-nginx установлен
# ============================================================================

echo "==> Checking ingress-nginx"

if ! kubectl get svc -n ingress-nginx ingress-nginx-controller > /dev/null 2>&1; then
    echo "❌ ingress-nginx не установлен. Сначала запустите setup-ingress-nginx.sh"
    exit 1
fi

INGRESS_CLASS=$(kubectl get ingressclass nginx -o jsonpath='{.metadata.name}' 2>/dev/null || true)
if [ -z "$INGRESS_CLASS" ]; then
    echo "❌ IngressClass 'nginx' не найден"
    exit 1
fi

echo "✅ ingress-nginx найден"

# ============================================================================
# 3. Создаём Secret для SMTP-пароля
# ============================================================================

echo "==> Creating SMTP password secret"

kubectl create secret generic "${SMTP_SECRET_NAME}" \
    --namespace "${NAMESPACE}" \
    --from-literal=password="${GRAFANA_SMTP_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Secret ${SMTP_SECRET_NAME} applied"

# ============================================================================
# 4. Добавляем Helm-репозиторий
# ============================================================================

echo "==> Adding prometheus-community Helm repository"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# ============================================================================
# 5. Устанавливаем / обновляем kube-prometheus-stack
# ============================================================================

echo "==> Installing/upgrading kube-prometheus-stack ${KUBE_PROM_STACK_VERSION}"

helm upgrade --install "${RELEASE_NAME}" prometheus-community/kube-prometheus-stack \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --version "${KUBE_PROM_STACK_VERSION}" \
    \
    --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}" \
    --set grafana.defaultDashboardsEnabled=false \
    --set grafana.sidecar.dashboards.enabled=true \
    --set grafana.sidecar.dashboards.label=grafana_dashboard \
    --set grafana.sidecar.dashboards.searchNamespace=ALL \
    \
    --set 'grafana.grafana\.ini.smtp.enabled=true' \
    --set 'grafana.grafana\.ini.smtp.host=smtp.gmail.com:587' \
    --set 'grafana.grafana\.ini.smtp.user='"${GRAFANA_SMTP_EMAIL}" \
    --set 'grafana.grafana\.ini.smtp.from_address='"${GRAFANA_SMTP_EMAIL}" \
    --set 'grafana.grafana\.ini.smtp.from_name=Grafana' \
    --set 'grafana.grafana\.ini.smtp.skip_verify=true' \
    --set 'grafana.grafana\.ini.smtp.password=$__file{/etc/secrets/smtp-password/password}' \
    --set 'grafana.extraSecretMounts[0].name='"${SMTP_SECRET_NAME}" \
    --set 'grafana.extraSecretMounts[0].secretName='"${SMTP_SECRET_NAME}" \
    --set 'grafana.extraSecretMounts[0].mountPath=/etc/secrets/smtp-password' \
    --set 'grafana.extraSecretMounts[0].readOnly=true' \
    --set 'grafana.extraSecretMounts[0].defaultMode=0400' \
    \
    --set 'grafana.grafana\.ini.server.root_url=%(protocol)s://%(domain)s:%(http_port)s/monitoring' \
    --set 'grafana.grafana\.ini.server.serve_from_sub_path=true' \
    --set grafana.ingress.enabled=true \
    --set grafana.ingress.ingressClassName=nginx \
    --set 'grafana.ingress.hosts[0]=' \
    --set grafana.ingress.path=/monitoring \
    --set grafana.ingress.pathType=Prefix \
    --set-string "grafana.ingress.annotations.nginx\.ingress\.kubernetes\.io/ssl-redirect=false" \
    \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
    --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
    --set prometheus.prometheusSpec.retention=7d \
    --set prometheus.prometheusSpec.retentionSize=10GiB \
    --set prometheus.prometheusSpec.resources.requests.cpu=200m \
    --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
    --set prometheus.prometheusSpec.resources.limits.cpu=1000m \
    --set prometheus.prometheusSpec.resources.limits.memory=2Gi \
    \
    --set alertmanager.enabled=false \
    --set grafana.sidecar.alerts.enabled=true \
    --set grafana.sidecar.alerts.label=grafana_alert \
    --set grafana.sidecar.alerts.labelValue="1" \
    --set grafana.sidecar.alerts.searchNamespace=ALL \
    \
    --set defaultRules.create=false \
    --set defaultRules.rules.alertmanager=false \
    --set defaultRules.rules.etcd=false \
    --set defaultRules.rules.general=false \
    --set defaultRules.rules.k8s=false \
    --set defaultRules.rules.kubeApiserverAvailability=false \
    --set defaultRules.rules.kubeApiserverBurnrate=false \
    --set defaultRules.rules.kubeApiserverHistogram=false \
    --set defaultRules.rules.kubeApiserverSlos=false \
    --set defaultRules.rules.kubeControllerManager=false \
    --set defaultRules.rules.kubelet=false \
    --set defaultRules.rules.kubeProxy=false \
    --set defaultRules.rules.kubePrometheus=false \
    --set defaultRules.rules.kubeScheduler=false \
    --set defaultRules.rules.kubeStateMetrics=false \
    --set defaultRules.rules.network=false \
    --set defaultRules.rules.node=false \
    --set defaultRules.rules.nodeExporterAlerting=false \
    --set defaultRules.rules.nodeExporterRecording=false \
    --set defaultRules.rules.prometheus=false \
    --set defaultRules.rules.prometheusOperator=false \
    \
    --wait \
    --timeout 10m

# ============================================================================
# 6. Проверка
# ============================================================================

echo "==> Waiting for Grafana to get external IP"

for i in $(seq 1 60); do
    GRAFANA_IP=$(kubectl get ingress -n "${NAMESPACE}" "${RELEASE_NAME}-grafana" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

    if [ -n "$GRAFANA_IP" ]; then
        echo "✅ Grafana ingress address: ${GRAFANA_IP}"
        break
    fi

    echo "   Attempt $i/60: waiting for ingress address..."
    sleep 5
done

echo ""
echo "📋 Monitoring stack установлен:"
echo "   Namespace:    ${NAMESPACE}"
echo "   Release:      ${RELEASE_NAME}"
echo "   Grafana URL:  http://${GRAFANA_IP:-<EXTERNAL-IP>}/monitoring"
echo "   Login:        admin / <GRAFANA_ADMIN_PASSWORD>"
echo "   SMTP email:   ${GRAFANA_SMTP_EMAIL}"
echo ""
echo "   Проверка:"
echo "     kubectl get pods -n ${NAMESPACE}"
echo "     curl -I http://${GRAFANA_IP:-<EXTERNAL-IP>}/monitoring"
echo ""
echo "   SMTP secret: ${SMTP_SECRET_NAME} (namespace ${NAMESPACE})"
echo "   Проверка SMTP в Grafana:"
echo "     Alerting → Contact points → Test"

# ============================================================================
# 7. Очистка
# ============================================================================

rm -f /tmp/kubeconfig-admin

echo ""
echo "✅ Monitoring setup complete for ${ENV}"