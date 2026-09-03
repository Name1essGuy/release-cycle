# modules/kubernetes-cluster/variables.tf

variable "environment" {
  description = "Окружение (dev, staging, prod)"
  type        = string
}

variable "control_plane_instance_type" {
  description = "Тип инстанса для control-plane (CPU, RAM)"
  type        = string
  default     = "s2.medium" # 2 vCPU, 4 GB RAM
}

variable "worker_instance_type" {
  description = "Тип инстанса для worker нод"
  type        = string
  default     = "s2.medium"
}

variable "worker_count" {
  description = "Количество worker нод"
  type        = number
  default     = 1
}

variable "control_plane_disk_size" {
  description = "Размер диска control-plane в ГБ"
  type        = number
  default     = 30
}

variable "worker_disk_size" {
  description = "Размер диска worker нод в ГБ"
  type        = number
  default     = 30
}

variable "subnet_ids" {
  description = "Список ID подсетей для размещения нод"
  type        = list(string)
}

variable "control_plane_security_group_id" {
  description = "ID security группы для control-plane"
  type        = string
}

variable "workers_security_group_id" {
  description = "ID security группы для worker нод"
  type        = string
}

variable "ssh_public_key" {
  description = "Публичный SSH ключ для доступа к VM"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Путь к приватному SSH-ключу для подключения к control-plane (должен быть без пароля)"
  type        = string
  default     = "~/.ssh/id_rsa_terraform"
}

variable "pod_network_cidr" {
  description = "CIDR блок для сети подов"
  type        = string
  default     = "10.244.0.0/16" # Flannel default
}

variable "service_network_cidr" {
  description = "CIDR блок для сервисов"
  type        = string
  default     = "10.96.0.0/12"
}

variable "kubernetes_version" {
  description = "Версия Kubernetes"
  type        = string
  default     = "1.28.2"
}

variable "zones" {
  description = "Список зон доступности для распределения нод"
  type        = list(string)
  default     = ["ru-central1-a", "ru-central1-b"]
}

variable "tags" {
  description = "Дополнительные теги"
  type        = map(string)
  default     = {}
}

variable "cluster_name" {
  description = "Имя кластера"
  type        = string
  default     = "k8s-cluster"
}