# modules/kubernetes-cluster/variables.tf

variable "environment" {
  description = "Окружение (dev, staging, prod)"
  type        = string
}

variable "folder_id" {
  description = "ID каталога в Yandex Cloud"
  type        = string
}

variable "network_id" {
  description = "ID VPC-сети"
  type        = string
}

variable "subnet_id" {
  description = "ID подсети для кластера и узлов"
  type        = string
}

variable "zone" {
  description = "Зона доступности"
  type        = string
  default     = "ru-central1-a"
}

variable "k8s_version" {
  description = "Версия Kubernetes"
  type        = string
  default     = "1.32"
}

variable "worker_count" {
  description = "Количество worker-нод"
  type        = number
  default     = 1
}

variable "worker_cores" {
  description = "Количество CPU на worker-ноде"
  type        = number
  default     = 2
}

variable "worker_memory" {
  description = "Объём RAM на worker-ноде (ГБ)"
  type        = number
  default     = 4
}

variable "worker_disk_size" {
  description = "Размер диска worker-ноды (ГБ)"
  type        = number
  default     = 30
}

variable "cluster_security_group_id" {
  description = "ID security group для кластера"
  type        = string
}

variable "worker_security_group_id" {
  description = "ID security group для worker-нод"
  type        = string
}

variable "tags" {
  description = "Дополнительные теги"
  type        = map(string)
  default     = {}
}