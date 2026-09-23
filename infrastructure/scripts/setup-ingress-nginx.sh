#!/bin/bash
# infrastructure/scripts/setup-ingress-nginx.sh
#
# Устанавливает ingress-nginx в кластер как cluster-wide инфраструктурный
# компонент. Запускается один раз, требует админский kubeconfig.
#
# Использование:
#   ./scripts/setup-ingress-nginx.sh staging
#
# Переменные окружения:
#   INGRESS_LB_SG_ID - ID security group для LoadBalancer (из terraform output)
#                      Если не задан, скрипт возьмёт значение из `terraform output`.
#   INGRESS_NGINX_VERSION - версия chart (по умолчанию 4.11.0)

set -e

ENV=${1:-staging}
NAMESPACE="ingress-nginx"
RELEASE_NAME="ingress-nginx"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

INGRESS_NGINX_VERSION="${INGRESS_NGINX_VERSION:-4.11.0}"

echo "🔧 Setting up ingress-nginx for environment: $ENV"

# ============================================================================
# 1. Получаем ID security group для LoadBalancer
# ============================================================================

if [ -z "$INGRESS_LB_SG_ID" ]; then
    echo "==> INGRESS_LB_SG_ID не задан, пытаемся получить из terraform output"

    if [ -d "$PROJECT_DIR" ]; then
        cd "$PROJECT_DIR"
        INGRESS_LB_SG_ID=$(terraform output -raw ingress_lb_security_group_id 2>/dev/null || true)
    fi

    if [ -z "$INGRESS_LB_SG_ID" ]; then
        echo "❌ Не удалось получить ingress_lb_security_group_id"
        echo "   Экспортируйте: export INGRESS_LB_SG_ID=<sg-id>"
        echo "   Или запустите из директории infrastructure/ с рабочим terraform workspace"
        exit 1
    fi
fi

echo "==> Using ingress_lb_security_group_id: $INGRESS_LB_SG_ID"

# ============================================================================
# 2. Получаем админский kubeconfig
# ============================================================================

echo "==> Fetching admin kubeconfig for $ENV"

yc managed-kubernetes cluster get-credentials \
    --name "${ENV}-managed-k8s" \
    --external \
    --force \
    --kubeconfig /tmp/kubeconfig-admin

export KUBECONFIG=/tmp/kubeconfig-admin

# Проверяем, что kubeconfig работает
if ! kubectl get nodes > /dev/null 2>&1; then
    echo "❌ Kubeconfig не работает. Проверьте доступ к кластеру ${ENV}-managed-k8s"
    exit 1
fi

echo "✅ Kubeconfig works"

# ============================================================================
# 3. Добавляем репозиторий ingress-nginx
# ============================================================================

echo "==> Adding ingress-nginx Helm repository"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# ============================================================================
# 4. Устанавливаем / обновляем ingress-nginx
# ============================================================================

echo "==> Installing/upgrading ingress-nginx ${INGRESS_NGINX_VERSION}"

helm upgrade --install "${RELEASE_NAME}" ingress-nginx/ingress-nginx \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --version "${INGRESS_NGINX_VERSION}" \
    --set controller.service.annotations."yandex\.cloud/load-balancer-type"=external \
    --set controller.service.annotations."yandex\.cloud/security-group-ids"="${INGRESS_LB_SG_ID}" \
    --set controller.admissionWebhooks.enabled=false \
    --set controller.config.use-proxy-protocol=false \
    --set controller.config.use-forwarded-headers=true \
    --set controller.metrics.enabled=true \
    --set controller.metrics.serviceMonitor.enabled=true \
    --set controller.metrics.serviceMonitor.additionalLabels.release="monitoring" \
    --wait \
    --timeout 5m

# ============================================================================
# 5. Проверка
# ============================================================================

echo "==> Waiting for LoadBalancer to get external IP"

for i in $(seq 1 60); do
    EXTERNAL_IP=$(kubectl get svc "${RELEASE_NAME}-controller" -n "${NAMESPACE}" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

    if [ -n "$EXTERNAL_IP" ]; then
        echo "✅ LoadBalancer external IP: ${EXTERNAL_IP}"
        break
    fi

    echo "   Attempt $i/60: waiting for external IP..."
    sleep 5
done

if [ -z "$EXTERNAL_IP" ]; then
    echo "⚠️  External IP не появился за 5 минут."
    echo "    Проверьте: kubectl get svc -n ${NAMESPACE}"
else
    echo ""
    echo "📋 ingress-nginx установлен:"
    echo "   Namespace:  ${NAMESPACE}"
    echo "   Release:    ${RELEASE_NAME}"
    echo "   External IP: ${EXTERNAL_IP}"
    echo ""
    echo "   Проверка: curl -I http://${EXTERNAL_IP}/"
fi

# ============================================================================
# 6. Очистка
# ============================================================================

rm -f /tmp/kubeconfig-admin

echo ""
echo "✅ ingress-nginx setup complete for ${ENV}"