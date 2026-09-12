# bootstrap/main.tf

terraform {
  required_version = ">= 1.5.0"
}

# ============================================================================
# 1. Создание сервисного аккаунта
# ============================================================================

resource "yandex_iam_service_account" "state_sa" {
  name        = var.service_account_name
  description = "Сервисный аккаунт для Terraform и Container Registry"
}

# ============================================================================
# 2. Назначение ролей сервисному аккаунту
# ============================================================================

resource "yandex_resourcemanager_folder_iam_member" "storage_editor" {
  folder_id = var.folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.state_sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "container_registry_editor" {
  folder_id = var.folder_id
  role      = "container-registry.editor"
  member    = "serviceAccount:${yandex_iam_service_account.state_sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "load_balancer_editor" {
  folder_id = var.folder_id
  role      = "load-balancer.admin"
  member    = "serviceAccount:${yandex_iam_service_account.state_sa.id}"
}

# ============================================================================
# 3. Создание статического ключа доступа
# ============================================================================

resource "yandex_iam_service_account_static_access_key" "state_sa_key" {
  service_account_id = yandex_iam_service_account.state_sa.id
  description        = "Static access key for Terraform state bucket"
}

# ============================================================================
# 4. Создание S3-бакета для состояния
# ============================================================================

resource "yandex_storage_bucket" "terraform_state" {
  bucket   = var.bucket_name
  max_size = 10737418240
  #access_key = yandex_iam_service_account_static_access_key.state_sa_key.access_key
  #secret_key = yandex_iam_service_account_static_access_key.state_sa_key.secret_key

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "expire-old-versions"
    enabled = true
    expiration {
      days = 30
    }
  }

  tags = {
    Environment = "bootstrap"
    ManagedBy   = "terraform"
    Purpose     = "terraform-state-storage"
  }
}

# ============================================================================
# 5. Создание S3-бакета для статики
# ============================================================================

resource "yandex_storage_bucket" "frontend_static" {
  bucket = var.frontend_bucket_name

  # Анонимный доступ: чтение и просмотр списка объектов
  anonymous_access_flags {
    read = true
    list = false
  }

  # Настройка хостинга статического сайта
  website {
    index_document = "index.html"
    error_document = "index.html"
  }

  # Версионирование отключено (статика обновляется часто)
  versioning {
    enabled = false
  }

  tags = {
    environment = "shared"
    managed_by  = "terraform"
    purpose     = "frontend-static-hosting"
  }
}

# Публичный доступ к объектам
resource "yandex_storage_bucket_iam_binding" "frontend_public" {
  bucket = yandex_storage_bucket.frontend_static.bucket
  role   = "storage.viewer"
  members = [
    "system:allUsers"
  ]
}

# ============================================================================
# 5. Создание Container Registry
# ============================================================================

resource "yandex_container_registry" "main" {
  name      = var.registry_name
  folder_id = var.folder_id
  labels = {
    environment = "bootstrap"
    managed_by  = "terraform"
  }
}

# ============================================================================
# 6. Создание статического ключа для Docker
# ============================================================================

resource "yandex_iam_service_account_static_access_key" "docker_key" {
  service_account_id = yandex_iam_service_account.state_sa.id
  description        = "Docker registry access key"
}

# ============================================================================
# 7. Создание ключа для сервисного аккаунта Terraform
# ============================================================================

resource "yandex_iam_service_account_key" "terraform_sa_key" {
  service_account_id = yandex_iam_service_account.state_sa.id
  description        = "Authorized key for Terraform"
}