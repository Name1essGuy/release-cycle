#!/bin/bash
# infrastructure/scripts/get-kubeconfig.sh

set -e

ENV=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔑 Getting kubeconfig for environment: $ENV"

cd "$PROJECT_DIR" || exit 1

# Получаем публичный IP control-plane
CONTROL_PLANE_IP=$(terraform output -raw control_plane_nat_ip 2>/dev/null || echo "")

if [ -z "$CONTROL_PLANE_IP" ]; then
    echo "❌ Error: Could not get control-plane IP"
    echo "Make sure you have applied Terraform for $ENV environment"
    exit 1
fi

echo "ℹ️ Control-plane IP: $CONTROL_PLANE_IP"

# Получаем kubeconfig через sudo cat
echo "ℹ️ Downloading kubeconfig from control-plane..."
ssh -o StrictHostKeyChecking=no ubuntu@$CONTROL_PLANE_IP "sudo cat /etc/kubernetes/admin.conf" > ./kubeconfig-$ENV

if [ ! -s ./kubeconfig-$ENV ]; then
    echo "❌ Error: kubeconfig is empty. Check that cluster is initialized."
    exit 1
fi

echo "ℹ️ Configuring kubeconfig..."

# ✅ Заменяем server на IP
sed -i "s|server: https://.*:6443|server: https://$CONTROL_PLANE_IP:6443|g" ./kubeconfig-$ENV

# ✅ Добавляем insecure-skip-tls-verify
if ! grep -q "insecure-skip-tls-verify:" ./kubeconfig-$ENV; then
    sed -i "/server: https:\/\/$CONTROL_PLANE_IP:6443/a\    insecure-skip-tls-verify: true" ./kubeconfig-$ENV
fi

# ✅ Удаляем certificate-authority-data
sed -i "/certificate-authority-data:/d" ./kubeconfig-$ENV

echo "ℹ️ Updated server to: https://$CONTROL_PLANE_IP:6443"

# Настраиваем контекст
export KUBECONFIG="./kubeconfig-$ENV"
kubectl config set-context kubernetes-admin@kubernetes --namespace=default --kubeconfig=./kubeconfig-$ENV

# Проверяем
echo "ℹ️ Testing connection to cluster..."
if kubectl get nodes &>/dev/null; then
    echo "✅ Connection successful!"
    echo ""
    kubectl get nodes
else
    echo "⚠️ Connection failed. Trying with explicit flags..."
    kubectl get nodes --insecure-skip-tls-verify=true
fi

echo ""
echo "✅ kubeconfig saved to: $(pwd)/kubeconfig-$ENV"
echo ""
echo "🔧 Use with:"
echo "export KUBECONFIG=$(pwd)/kubeconfig-$ENV"
echo "kubectl get nodes"