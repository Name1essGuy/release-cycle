# bootstrap/outputs.tf

output "bucket_name" {
  description = "Имя созданного S3-бакета"
  value       = yandex_storage_bucket.terraform_state.bucket
}

output "registry_id" {
  description = "ID созданного Container Registry"
  value       = yandex_container_registry.main.id
}

output "registry_name" {
  description = "Имя созданного Container Registry"
  value       = yandex_container_registry.main.name
}

output "registry_url" {
  description = "URL Container Registry"
  value       = "cr.yandex/${yandex_container_registry.main.id}"
}

output "service_account_id" {
  description = "ID созданного сервисного аккаунта"
  value       = yandex_iam_service_account.state_sa.id
}

output "access_key" {
  description = "Access Key для S3"
  value       = yandex_iam_service_account_static_access_key.state_sa_key.access_key
  sensitive   = true
}

output "secret_key" {
  description = "Secret Key для S3"
  value       = yandex_iam_service_account_static_access_key.state_sa_key.secret_key
  sensitive   = true
}

output "docker_access_key" {
  description = "Access Key для Docker Registry"
  value       = yandex_iam_service_account_static_access_key.docker_key.access_key
  sensitive   = true
}

output "docker_secret_key" {
  description = "Secret Key для Docker Registry"
  value       = yandex_iam_service_account_static_access_key.docker_key.secret_key
  sensitive   = true
}