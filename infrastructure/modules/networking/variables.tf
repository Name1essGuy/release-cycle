# modules/networking/variables.tf

variable "environment" {
  description = "Окружение (dev, staging, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR блок для VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidrs" {
  description = "Список CIDR блоков для подсетей"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "zones" {
  description = "Зоны доступности для подсетей"
  type        = list(string)
  default     = ["ru-central1-a", "ru-central1-b"]
}

variable "enable_nat" {
  description = "Включить NAT Gateway для доступа в интернет"
  type        = bool
  default     = true
}

variable "ssh_allowed_cidrs" {
  description = "CIDR блоки, с которых разрешен SSH доступ"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "api_allowed_cidrs" {
  description = "CIDR блоки, с которых разрешен доступ к Kubernetes API (6443)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Дополнительные теги для ресурсов"
  type        = map(string)
  default     = {}
}