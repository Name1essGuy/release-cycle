# bootstrap/outputs.tf

# Важные данные для использования в основном проекте
output "bucket_name" {
  description = "Имя созданного S3-бакета"
  value       = yandex_storage_bucket.terraform_state.bucket
}

output "service_account_id" {
  description = "ID созданного сервисного аккаунта"
  value       = yandex_iam_service_account.state_sa.id
}

output "access_key" {
  description = "Access Key для сервисного аккаунта"
  value       = yandex_iam_service_account_static_access_key.state_sa_key.access_key
  sensitive   = true
}

output "secret_key" {
  description = "Secret Key для сервисного аккаунта"
  value       = yandex_iam_service_account_static_access_key.state_sa_key.secret_key
  sensitive   = true
}

# Эти данные нужно использовать в backend.tf основного проекта
output "backend_configuration" {
  description = "Конфигурация для backend.tf основного проекта"
  value = {
    endpoint   = "storage.yandexcloud.net"
    bucket     = yandex_storage_bucket.terraform_state.bucket
    region     = "ru-central1"
    access_key = yandex_iam_service_account_static_access_key.state_sa_key.access_key
    secret_key = yandex_iam_service_account_static_access_key.state_sa_key.secret_key
  }
  sensitive = true
}