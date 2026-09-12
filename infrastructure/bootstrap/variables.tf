# bootstrap/variables.tf

variable "cloud_id" {
  description = "ID облака в Yandex Cloud"
  type        = string
}

variable "folder_id" {
  description = "ID каталога в Yandex Cloud"
  type        = string
}

variable "bucket_name" {
  description = "Имя S3-бакета для хранения state-файлов"
  type        = string
  default     = "my-terraform-state-bucket"
}

variable "registry_name" {
  description = "Имя Container Registry"
  type        = string
  default     = "momo-store-registry"
}

variable "service_account_name" {
  description = "Имя сервисного аккаунта"
  type        = string
  default     = "terraform-sa"
}

variable "frontend_bucket_name" {
  description = "Имя бакета для статики фронтенда"
  type        = string
  default     = "momo-store-frontend"
}

variable "zone" {
  description = "Зона доступности по умолчанию"
  type        = string
  default     = "ru-central1-a"
}