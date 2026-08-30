# Модуль Kubernetes Cluster

## 📋 Описание
Модуль создает полноценный Kubernetes кластер в Yandex Cloud с использованием kubeadm.

## 🎯 Что создает
- Control-plane ноду (master)
- Worker ноды (количество настраивается)
- Установленный containerd
- Инициализированный кластер с Calico
- Готовый kubeconfig

## 📥 Входные параметры (variables)

| Параметр | Тип | Описание |
| :--- | :--- | :--- |
| `environment` | string | Окружение (dev, staging, prod) |
| `worker_count` | number | Количество worker нод |
| `subnet_ids` | list(string) | ID подсетей для нод |
| `ssh_public_key` | string | Публичный SSH ключ |
| `kubernetes_version` | string | Версия Kubernetes |

## 📤 Выходные данные (outputs)

| Выход | Описание |
| :--- | :--- |
| `control_plane_ip` | Внутренний IP мастер-ноды |
| `control_plane_nat_ip` | Публичный IP мастер-ноды |
| `worker_ips` | Список IP worker-нод |
| `cluster_endpoint` | Kubernetes API endpoint |
| `get_kubeconfig_command` | Команда для получения kubeconfig |

## 🚀 Использование

```hcl
module "kubernetes_cluster" {
  source = "./modules/kubernetes-cluster"
  
  environment  = "dev"
  worker_count = 1
  subnet_ids   = module.networking.subnet_ids
  ssh_public_key = file("~/.ssh/id_rsa.pub")
}
```

## 🔗 Доступ к кластеру

```bash
# Получить kubeconfig
${module.kubernetes_cluster.get_kubeconfig_command}

# Использовать кластер
kubectl --kubeconfig=./kubeconfig-dev get nodes
```

## 🔧 Управление кластером

```bash
# SSH на мастер
ssh ubuntu@<master_public_ip>

# Проверка статуса нод
kubectl get nodes

# Проверка подов
kubectl get pods -A
```