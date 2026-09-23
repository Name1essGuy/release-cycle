#!/bin/bash
# infrastructure/scripts/verify.sh
#
# Проверка работоспособности Momo Store после деплоя.
#
# Что проверяет:
#   1. Поды backend/frontend готовы.
#   2. ServiceMonitor и ConfigMap'ы мониторинга созданы.
#   3. Сайт открывается по EXTERNAL-IP ingress-nginx.
#   4. Статика проксируется как JS.
#   5. API /api/products возвращает JSON.

set -e

NAMESPACE="${NAMESPACE:-default}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
INGRESS_NAMESPACE="${INGRESS_NAMESPACE:-ingress-nginx}"
RELEASE_NAME="${RELEASE_NAME:-momo-store}"

echo "🔍 Verifying $RELEASE_NAME in namespace $NAMESPACE"

# ============================================================================
# 1. Поды готовы
# ============================================================================

echo ""
echo "==> Checking deployments"

kubectl rollout status deploy/"$RELEASE_NAME"-backend -n "$NAMESPACE" --timeout=60s
kubectl rollout status deploy/"$RELEASE_NAME"-frontend -n "$NAMESPACE" --timeout=60s

echo "✅ Deployments are ready"

# ============================================================================
# 2. Ресурсы мониторинга
# ============================================================================

echo ""
echo "==> Checking monitoring resources"

if kubectl get servicemonitor -n "$NAMESPACE" "$RELEASE_NAME"-backend > /dev/null 2>&1; then
    echo "✅ ServiceMonitor/$RELEASE_NAME-backend exists"
else
    echo "⚠️  ServiceMonitor/$RELEASE_NAME-backend not found"
fi

if kubectl get configmap -n "$NAMESPACE" "$RELEASE_NAME"-grafana-dashboards > /dev/null 2>&1; then
    echo "✅ ConfigMap/$RELEASE_NAME-grafana-dashboards exists"
else
    echo "⚠️  ConfigMap/$RELEASE_NAME-grafana-dashboards not found"
fi

# ============================================================================
# 3. Внешний IP
# ============================================================================

echo ""
echo "==> Getting external IP of ingress-nginx"

EXTERNAL_IP=$(kubectl get svc -n "$INGRESS_NAMESPACE" ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

if [ -z "$EXTERNAL_IP" ]; then
    echo "❌ EXTERNAL-IP ingress-nginx not found"
    exit 1
fi

echo "✅ EXTERNAL-IP: $EXTERNAL_IP"

# ============================================================================
# 4. Корень сайта
# ============================================================================

echo ""
echo "==> Testing site root"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$EXTERNAL_IP/" || echo "000")
if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ GET / — HTTP $HTTP_CODE (expected 200)"
    exit 1
fi
echo "✅ GET / — 200"

# ============================================================================
# 5. Статика как JS
# ============================================================================

echo ""
echo "==> Testing static asset (JS)"

JS_PATH="/momo-store/js/app.82cde13b.js"
CT=$(curl -s -o /dev/null -w "%{content_type}" --max-time 10 "http://$EXTERNAL_IP$JS_PATH" || echo "")
echo "Content-Type: $CT"

case "$CT" in
    *javascript*|*ecmascript*)
        echo "✅ Static is proxied as JavaScript"
        ;;
    *)
        echo "❌ Static returned as '$CT' (expected JavaScript)"
        exit 1
        ;;
esac

# ============================================================================
# 6. API
# ============================================================================

echo ""
echo "==> Testing API"

API_BODY=$(curl -s --max-time 10 "http://$EXTERNAL_IP/api/products" || echo "")

if ! echo "$API_BODY" | grep -q '"results"'; then
    echo "❌ /api/products returned unexpected body"
    echo "   Got: $(echo "$API_BODY" | head -c 100)"
    exit 1
fi
echo "✅ /api/products returns JSON with results"

# ============================================================================
# Итог
# ============================================================================

echo ""
echo "✅ All checks passed!"
echo "   Site: http://$EXTERNAL_IP/"