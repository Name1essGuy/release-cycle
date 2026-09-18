#!/bin/bash
# modules/gitlab-runner/scripts/install-runner.sh

set -e

export DEBIAN_FRONTEND=noninteractive

exec > >(tee /var/log/user-data.log)

# ============================================================================
# 1. Установка Docker
# ============================================================================

echo "==> Installing Docker"
curl -fsSL https://get.docker.com | sh

# Добавляем пользователя ubuntu в группу docker
usermod -aG docker ubuntu

# Запускаем Docker
systemctl enable --now docker

# ============================================================================
# 2. Запуск GitLab Runner
# ============================================================================

echo "==> Starting GitLab Runner"
sudo docker run -d \
  --name gitlab-runner \
  --restart always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /etc/gitlab-runner:/etc/gitlab-runner \
  gitlab/gitlab-runner:latest

# ============================================================================
# 3. Ожидание готовности Runner
# ============================================================================

echo "==> Waiting for Runner"
sleep 10

# ============================================================================
# 4. Регистрация Runner
# ============================================================================

echo "==> Registering Runner"
sudo docker exec gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "${gitlab_url}" \
  --token "${gitlab_token}" \
  --executor "docker" \
  --docker-image "alpine:latest" \
  --description "${environment}-runner"

# ============================================================================
# 5. Настройка config.toml: privileged + volumes для dind
# ============================================================================

echo "==> Installing yq for TOML manipulation"
sudo wget -qO /usr/local/bin/yq \
  https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

CONFIG=/etc/gitlab-runner/config.toml

echo "==> Patching config.toml: privileged = true"
sudo yq -i '.runners[0].docker.privileged = true' "$CONFIG"

echo "==> Patching config.toml: volumes without /var/run/docker.sock"
sudo yq -i '.runners[0].docker.volumes = ["/cache", "/certs/client"]' "$CONFIG"

echo "==> New config.toml:"
sudo cat "$CONFIG"

# ============================================================================
# 6. Перезапуск runner для применения конфига
# ============================================================================

echo "==> Restarting gitlab-runner"
sudo docker restart gitlab-runner
sleep 5

# ============================================================================
# 7. Проверка
# ============================================================================

echo "==> Done"
sudo docker exec gitlab-runner gitlab-runner list