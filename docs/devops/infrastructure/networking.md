# Модуль Networking

## 📋 Описание
Модуль создает сетевую инфраструктуру для Kubernetes кластера в Yandex Cloud.

## 🎯 Что создает
- VPC (изолированная сеть)
- Подсети в разных зонах доступности
- NAT Gateway для доступа в интернет
- Security Groups с правилами файрвола для всех компонентов

## 📥 Входные параметры (variables)

| Параметр | Тип | Описание |
| :--- | :--- | :--- |
| `environment` | string | Окружение (dev, staging, prod) |
| `vpc_cidr` | string | CIDR блок для VPC |
| `subnet_cidrs` | list(string) | CIDR блоки для подсетей |
| `zones` | list(string) | Зоны доступности |
| `enable_nat` | bool | Включить NAT Gateway |
| `ssh_allowed_cidrs` | list(string) | Разрешенные CIDR для SSH |
| `api_allowed_cidrs` | list(string) | Разрешенные CIDR для K8s API |

## 📤 Выходные данные (outputs)

| Выход | Описание |
| :--- | :--- |
| `vpc_id` | ID VPC |
| `subnet_ids` | Список ID подсетей |
| `control_plane_security_group_id` | ID security group для мастера |
| `workers_security_group_id` | ID security group для воркеров |
| `gitlab_runner_security_group_id` | ID security group для раннера |

## 🚀 Использование

```hcl
module "networking" {
  source = "./modules/networking"
  
  environment  = "dev"
  vpc_cidr     = "10.0.0.0/16"
  subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  zones        = ["ru-central1-a", "ru-central1-b"]
  enable_nat   = true
  
  ssh_allowed_cidrs  = ["0.0.0.0/0"]
  api_allowed_cidrs  = ["0.0.0.0/0"]
}
