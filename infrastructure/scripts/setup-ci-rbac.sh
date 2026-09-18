#!/bin/bash
# infrastructure/scripts/setup-ci-rbac.sh
#
# Настраивает RBAC в Kubernetes кластере для GitLab CI:
# 1. Создаёт ServiceAccount ci-deployer в namespace default.
# 2. Создаёт Role и RoleBinding с правами на деплой.
# 3. Создаёт долгоживущий токен через Secret.
# 4. Формирует kubeconfig с токеном.
# 5. Обновляет переменную KUBE_CONFIG_<ENV> в GitLab через API.

set -e

ENV=${1:-staging}
NAMESPACE="default"
SA_NAME="ci-deployer"
SECRET_NAME="ci-deployer-token"

echo "🔧 Setting up CI RBAC for environment: $ENV"

# ============================================================================
# Проверка переменных окружения
# ============================================================================

if [ -z "$GITLAB_TOKEN" ]; then
    echo "⚠️  GITLAB_TOKEN не задан - переменная в GitLab не будет обновлена автоматически."
    echo "    Экспортируйте: export GITLAB_TOKEN=<personal-access-token>"
    echo "    И: export GITLAB_PROJECT_ID=<project-id>"
    SKIP_GITLAB_UPDATE=1
fi

if [ -z "$GITLAB_PROJECT_ID" ]; then
    echo "⚠️  GITLAB_PROJECT_ID не задан - переменная в GitLab не будет обновлена."
    SKIP_GITLAB_UPDATE=1
fi

GITLAB_URL="${GITLAB_URL:-https://praktikum.gitlab.yandexcloud.net}"

# ============================================================================
# 1. Получаем kubeconfig от YC (админский, для настройки)
# ============================================================================

echo "==> Fetching admin kubeconfig for $ENV"
yc managed-kubernetes cluster get-credentials \
    --name "${ENV}-managed-k8s" \
    --external \
    --force \
    --kubeconfig /tmp/kubeconfig-admin

export KUBECONFIG=/tmp/kubeconfig-admin

# ============================================================================
# 2. Создаём ServiceAccount, Role, RoleBinding
# ============================================================================

echo "==> Creating ServiceAccount, Role, RoleBinding"

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SA_NAME}
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${SA_NAME}
  namespace: ${NAMESPACE}
rules:
  # Core
  - apiGroups: [""]
    resources:
      - configmaps
      - secrets
      - services
      - serviceaccounts
      - persistentvolumeclaims
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - pods/exec
      - endpoints
      - events
      - replicasets
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources:
      - namespaces
    verbs: ["get", "list", "watch"]
  # Apps
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
      - statefulsets
      - daemonsets
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Batch
  - apiGroups: ["batch"]
    resources:
      - jobs
      - cronjobs
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Networking
  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  # Autoscaling
  - apiGroups: ["autoscaling"]
    resources:
      - horizontalpodautoscalers
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${SA_NAME}
  namespace: ${NAMESPACE}
subjects:
  - kind: ServiceAccount
    name: ${SA_NAME}
    namespace: ${NAMESPACE}
roleRef:
  kind: Role
  name: ${SA_NAME}
  apiGroup: rbac.authorization.k8s.io
EOF

# ============================================================================
# 3. Создаём долгоживущий токен
# ============================================================================

echo "==> Creating long-lived token Secret"

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SA_NAME}
type: kubernetes.io/service-account-token
EOF

# ============================================================================
# 4. Ждём, пока Kubernetes сгенерирует токен
# ============================================================================

echo "==> Waiting for token to be generated"

for i in $(seq 1 30); do
    TOKEN=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} \
        -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
    if [ -n "$TOKEN" ]; then
        echo "✅ Token obtained"
        break
    fi
    echo "   Attempt $i/30: waiting..."
    sleep 2
done

if [ -z "$TOKEN" ]; then
    echo "❌ Failed to obtain token after 60 seconds"
    exit 1
fi

# ============================================================================
# 5. Собираем kubeconfig
# ============================================================================

echo "==> Building kubeconfig"

CLUSTER_SERVER=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
CA_DATA=$(kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.ca\.crt}')

cat > /tmp/kubeconfig-ci <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CA_DATA}
    server: ${CLUSTER_SERVER}
  name: ${ENV}
contexts:
- context:
    cluster: ${ENV}
    namespace: ${NAMESPACE}
    user: ${SA_NAME}
  name: ${ENV}
current-context: ${ENV}
users:
- name: ${SA_NAME}
  user:
    token: ${TOKEN}
EOF

# Проверяем, что kubeconfig работает
echo "==> Verifying kubeconfig"

KUBECONFIG=/tmp/kubeconfig-ci kubectl get pods -n ${NAMESPACE} > /dev/null
echo "✅ kubeconfig works"

# ============================================================================
# 6. Обновляем переменную в GitLab
# ============================================================================

if [ -z "$SKIP_GITLAB_UPDATE" ]; then
    echo "==> Updating GitLab CI/CD variable KUBE_CONFIG_$(echo $ENV | tr '[:lower:]' '[:upper:]')"

    KUBE_CONFIG_B64=$(base64 -w0 /tmp/kubeconfig-ci)
    VAR_NAME="KUBE_CONFIG_$(echo $ENV | tr '[:lower:]' '[:upper:]')"

    # Проверяем, существует ли переменная
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/variables/${VAR_NAME}")

    if [ "$HTTP_CODE" = "200" ]; then
        # Обновляем
        curl -s --request PUT \
            --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
            --form "value=${KUBE_CONFIG_B64}" \
            "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/variables/${VAR_NAME}" \
            > /dev/null
        echo "✅ Variable ${VAR_NAME} updated"
    elif [ "$HTTP_CODE" = "404" ]; then
        # Создаём
        curl -s --request POST \
            --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
            --form "key=${VAR_NAME}" \
            --form "value=${KUBE_CONFIG_B64}" \
            --form "masked=false" \
            --form "protected=false" \
            "${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/variables" \
            > /dev/null
        echo "✅ Variable ${VAR_NAME} created"
    else
        echo "⚠️  Unexpected HTTP code: ${HTTP_CODE}"
        echo "    Kubeconfig сохранён в /tmp/kubeconfig-ci - вставьте вручную"
    fi
else
    echo "⚠️  Пропущено обновление GitLab. Kubeconfig в /tmp/kubeconfig-ci"
    echo "    Base64:"
    echo ""
    base64 -w0 /tmp/kubeconfig-ci
fi

# ============================================================================
# 7. Очистка
# ============================================================================

rm -f /tmp/kubeconfig-admin
# /tmp/kubeconfig-ci не удаляем - может понадобиться для отладки

echo ""
echo "✅ CI RBAC setup complete for ${ENV}"