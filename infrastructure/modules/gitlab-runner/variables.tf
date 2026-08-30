# modules/gitlab-runner/variables.tf

variable "environment" {
  description = "Окружение (dev, staging, prod)"
  type        = string
}

variable "gitlab_url" {
  description = "URL GitLab инстанса"
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_token" {
  description = "Токен для регистрации GitLab Runner"
  type        = string
  sensitive   = true
}

variable "subnet_id" {
  description = "ID подсети для размещения VM"
  type        = string
}

variable "security_group_ids" {
  description = "Список ID security групп"
  type        = list(string)
  default     = []
}

variable "ssh_public_key" {
  description = "Публичный SSH ключ для доступа к VM"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Путь к приватному SSH-ключу для подключения к VM"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "disk_size" {
  description = "Размер диска в ГБ"
  type        = number
  default     = 20
}

variable "tags" {
  description = "Теги для ресурсов"
  type        = map(string)
  default     = {}
}