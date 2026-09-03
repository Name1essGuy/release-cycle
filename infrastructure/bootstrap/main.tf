# bootstrap/main.tf

# 1. Создаем сервисный аккаунт
resource "yandex_iam_service_account" "state_sa" {
  name        = var.service_account_name
  description = "Сервисный аккаунт для доступа к S3 бакету с Terraform state"
}

# 2. Назначаем роль сервисному аккаунту
resource "yandex_resourcemanager_folder_iam_member" "storage_editor" {
  folder_id = var.folder_id
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.state_sa.id}"
}

# 3. Создаем статический ключ доступа для сервисного аккаунта
resource "yandex_iam_service_account_static_access_key" "state_sa_key" {
  service_account_id = yandex_iam_service_account.state_sa.id
  description        = "Статический ключ доступа к S3 бакету с Terraform state"
}

# 4. Создаем S3-бакет
resource "yandex_storage_bucket" "terraform_state" {
  bucket     = var.bucket_name
  max_size   = 10737418240 # 10 GB
  access_key = yandex_iam_service_account_static_access_key.state_sa_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.state_sa_key.secret_key

  # Включаем версионирование для защиты от случайного удаления
  versioning {
    enabled = true
  }

  # Настраиваем lifecycle политику
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

# 5. Создаем статический ключ для пользователя (для ручного доступа)
resource "yandex_iam_service_account_static_access_key" "user_key" {
  service_account_id = yandex_iam_service_account.state_sa.id
  description        = "Статический пользоватлеьский ключ для ручных операций"
}