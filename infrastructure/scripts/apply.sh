#!/bin/bash
# infrastructure/scripts/apply.sh

set -e

ENV=${1:-staging}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🚀 Applying Terraform for environment: $ENV"
echo "📁 Project directory: $PROJECT_DIR"

cd "$PROJECT_DIR" || exit 1

# Проверяем наличие переменных окружения
if [ -z "$YC_SERVICE_ACCOUNT_KEY_FILE" ]; then
    echo "❌ Error: YC_SERVICE_ACCOUNT_KEY_FILE is not set"
    echo "Please export: YC_SERVICE_ACCOUNT_KEY_FILE=/path/to/key.json"
    exit 1
fi

if [ -z "$YC_CLOUD_ID" ] || [ -z "$YC_FOLDER_ID" ]; then
    echo "❌ Error: YC_CLOUD_ID and YC_FOLDER_ID must be set"
    exit 1
fi

# Переключаемся на workspace
terraform workspace select "$ENV" || terraform workspace new "$ENV"

# Инициализация
echo "ℹ️ Initializing Terraform..."
terraform init

# Проверка формата
echo "ℹ️ Checking formatting..."
terraform fmt -check -recursive || terraform fmt -recursive

# Проверка синтаксиса
echo "ℹ️ Validating configuration..."
terraform validate

# План
echo "📋 Planning changes..."
terraform plan -var-file="environments/$ENV/terraform.tfvars"

# Применение
echo "🚀 Applying changes..."
terraform apply -var-file="environments/$ENV/terraform.tfvars" -auto-approve

# ============================================================================
# Post-apply: установка ingress-nginx (инфраструктурный компонент)
# ============================================================================

echo ""
echo "🔧 Setting up ingress-nginx for $ENV"
"$SCRIPT_DIR/setup-ingress-nginx.sh" "$ENV"

# ============================================================================
# Post-apply: установка monitoring (Prometheus + Grafana)
# ============================================================================

echo ""
echo "🔧 Setting up monitoring for $ENV"
"$SCRIPT_DIR/setup-monitoring.sh" "$ENV"

# ============================================================================
# Post-apply: настройка RBAC для CI
# ============================================================================

echo ""
echo "🔧 Setting up CI/CD RBAC for $ENV"
"$SCRIPT_DIR/setup-ci-rbac.sh" "$ENV"

echo ""
echo "✅ Done! Cluster $ENV is ready."