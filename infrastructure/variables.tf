# infrastructure/variables.tf

# ============================================================================
# Переменные для сетей
# ============================================================================

variable "vpc_cidr" {
  description = "CIDR блок для VPC в каждом окружении"
  type        = map(string)
  default = {
    dev     = "10.0.0.0/16"
    staging = "10.1.0.0/16"
    prod    = "10.2.0.0/16"
  }
}

variable "subnet_cidrs" {
  description = "CIDR блоки для подсетей в каждом окружении"
  type        = map(list(string))
  default = {
    dev     = ["10.0.1.0/24", "10.0.2.0/24"]
    staging = ["10.1.1.0/24", "10.1.2.0/24"]
    prod    = ["10.2.1.0/24", "10.2.2.0/24"]
  }
}

variable "zones" {
  description = "Зоны доступности для подсетей"
  type        = map(list(string))
  default = {
    dev     = ["ru-central1-a", "ru-central1-b"]
    staging = ["ru-central1-a", "ru-central1-b"]
    prod    = ["ru-central1-a", "ru-central1-b", "ru-central1-c"]
  }
}

# ============================================================================
# Переменные для Kubernetes кластера
# ============================================================================

variable "control_plane_instance_type" {
  description = "Тип инстанса для control-plane нод"
  type        = map(string)
  default = {
    dev     = "s2.micro"  # 2 vCPU, 2 GB RAM
    staging = "s2.medium" # 2 vCPU, 4 GB RAM
    prod    = "s2.large"  # 4 vCPU, 8 GB RAM
  }
}

variable "worker_instance_type" {
  description = "Тип инстанса для worker нод"
  type        = map(string)
  default = {
    dev     = "s2.micro"
    staging = "s2.medium"
    prod    = "s2.large"
  }
}

variable "worker_count" {
  description = "Количество worker нод"
  type        = map(number)
  default = {
    dev     = 1
    staging = 2
    prod    = 3
  }
}

variable "kubernetes_version" {
  description = "Версия Kubernetes"
  type        = string
  default     = "1.28.2"
}

variable "pod_network_cidr" {
  description = "CIDR блок для сети подов"
  type        = string
  default     = "10.244.0.0/16"
}

# ============================================================================
# Переменные для SSH и доступа
# ============================================================================

variable "ssh_public_key_path" {
  description = "Путь к публичному SSH-ключу"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_allowed_cidrs" {
  description = "CIDR блоки для SSH доступа"
  type        = map(list(string))
  default = {
    dev     = ["0.0.0.0/0"]
    staging = ["0.0.0.0/0"]
    prod    = ["0.0.0.0/0"]
  }
}

# ============================================================================
# Переменные для GitLab Runner
# ============================================================================

variable "gitlab_token" {
  description = "GitLab токен для регистрации раннера"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "gitlab_url" {
  description = "URL GitLab инстанса"
  type        = string
  default     = "https://gitlab.com"
}

variable "runner_registration_tags" {
  description = "Теги для регистрации раннера"
  type        = map(list(string))
  default = {
    dev     = ["docker", "dev"]
    staging = ["docker", "staging"]
    prod    = ["docker", "prod"]
  }
}

# ============================================================================
# Общие переменные
# ============================================================================

variable "tags" {
  description = "Общие теги для всех ресурсов"
  type        = map(string)
  default = {
    Project   = "kubernetes-learning"
    ManagedBy = "terraform"
  }
}