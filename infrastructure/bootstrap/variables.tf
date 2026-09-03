# bootstrap/variables.tf

variable "folder_id" {
  description = "ID каталога в Yandex Cloud"
  type        = string
}

variable "cloud_id" {
  description = "ID облака в Yandex Cloud"
  type        = string
}

variable "service_account_name" {
  description = "Имя сервисного аккаунта"
  type        = string
  default     = "terraform-sa"
}

variable "bucket_name" {
  description = "Имя S3-бакета"
  type        = string
  default     = "my-terraform-state-bucket"
}

variable "zone" {
  description = "Зона доступности"
  type        = string
  default     = "ru-central1-a"
}