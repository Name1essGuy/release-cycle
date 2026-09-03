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
# 2. Запуск GitLab Runner (через sudo)
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
# 4. Регистрация Runner (через sudo)
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
# 5. Проверка статуса (через sudo)
# ============================================================================

echo "==> Done"
sudo docker exec gitlab-runner gitlab-runner list