# Infrastructure as Code (IaC) для Kubernetes кластера

## 📋 Описание

Проект управляет инфраструктурой для Kubernetes-кластера в Yandex Cloud с использованием **Terraform**. Вся инфраструктура описана как код и разделена по окружениям через **Terraform Workspaces**: `staging`, `prod`.

Модуль `networking` создаёт VPC, подсети, NAT, security groups. Модуль `kubernetes-cluster` разворачивает managed Kubernetes. Модуль `gitlab-runner` — опционально — разворачивает ВМ с GitLab Runner.

---

## 🏗 Архитектура

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ Yandex Cloud                                                                 │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │ VPC (staging: 10.1.0.0/16, prod: 10.2.0.0/16)                          │  │
│  │                                                                        │  │
│  │   ┌───────────────┐    ┌───────────────┐    ┌───────────────┐          │  │
│  │   │  Subnet 1     │    │  Subnet 2     │    │  Subnet 3*    │          │  │
│  │   │ ru-central1-a │    │ ru-central1-b │    │ ru-central1-c │          │  │
│  │   └───────┬───────┘    └───────┬───────┘    └───────┬───────┘          │  │
│  │           │                    │                    │                  │  │
│  │   ┌───────▼────────────────────▼────────────────────▼───────┐          │  │
│  │   │ Security Groups                                         │          │  │
│  │   │  • <env>-sg-control-plane                               │          │  │
│  │   │  • <env>-sg-workers                                     │          │  │
│  │   │  • <env>-sg-gitlab-runner                               │          │  │
│  │   │  • <env>-sg-ingress-lb                                  │          │  │
│  │   └───────────────────────┬─────────────────────────────────┘          │  │
│  │                           │                                            │  │
│  │   ┌───────────────────────▼─────────────────────────────────┐          │  │
│  │   │ Managed Kubernetes (Yandex Cloud)                       │          │  │
│  │   │                                                         │          │  │
│  │   │  ┌────────────────────────────────────────┐             │          │  │
│  │   │  │ Control plane (managed by YC)          │             │          │  │
│  │   │  │  • kube-apiserver, etcd, scheduler     │             │          │  │
│  │   │  │  • controller-manager                  │             │          │  │
│  │   │  └────────────────────────────────────────┘             │          │  │
│  │   │                                                         │          │  │
│  │   │  ┌───────────────┐  ┌───────────────┐  ┌────────────┐   │          │  │
│  │   │  │ Worker 1      │  │ Worker 2      │  │ Worker N*  │   │          │  │
│  │   │  │ containerd    │  │ containerd    │  │ containerd │   │          │  │
│  │   │  │ kubelet,      │  │ kubelet,      │  │ kubelet,   │   │          │  │
│  │   │  │ kube-proxy    │  │ kube-proxy    │  │ kube-proxy │   │          │  │
│  │   │  └───────────────┘  └───────────────┘  └────────────┘   │          │  │
│  │   └─────────────────────────────────────────────────────────┘          │  │
│  │                                                                        │  │
│  │   ┌─────────────────────────────────────────────────────────┐          │  │
│  │   │ GitLab Runner (только staging/prod)                     │          │  │
│  │   │  • Docker executor                                      │          │  │
│  │   │  • kubectl, helm, yc                                    │          │  │
│  │   └─────────────────────────────────────────────────────────┘          │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │ S3 Bucket (Terraform state)                                            │  │
│  │   • infrastructure/staging/terraform.tfstate                           │  │
│  │   • infrastructure/prod/terraform.tfstate                              │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘

* Subnet 3 и Worker N появляются только в prod (3 подсети и 3 воркера).
```

---

## 📁 Структура проекта

```
infrastructure/
│
├── bootstrap/                       # Создаётся 1 раз вручную
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── terraform.tfvars.example
│
├── environments/                    # tfvars для каждого окружения
│   ├── staging/
│   │   ├── terraform.tfvars
│   │   └── terraform.tfvars.example
│   └── prod/
│       ├── terraform.tfvars
│       └── terraform.tfvars.example
│
├── modules/
│   ├── networking/                  # VPC, подсети, NAT, SG
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── kubernetes-cluster/          # Managed K8s
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── gitlab-runner/               # GitLab Runner
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── scripts/
│           └── install-runner.sh
│
├── scripts/
│   └── apply.sh                     # Применение для окружения
│
├── .gitignore
├── backend.tf                       # S3 backend для state
├── provider.tf                      # Провайдер Yandex Cloud
├── variables.tf                     # Глобальные переменные
├── main.tf                          # Вызов модулей
└── outputs.tf                       # Глобальные outputs
```

---

## 🔧 Предварительные требования

### 1. Установленное ПО

| Инструмент | Версия | Назначение |
|---|---|---|
| Terraform | ≥ 1.5.0 | Управление инфраструктурой |
| Yandex Cloud CLI | последняя | Взаимодействие с YC |
| kubectl | ≥ 1.28 | Управление Kubernetes |
| Git | последняя | Контроль версий |

### 2. Доступы в Yandex Cloud

- Аккаунт в Yandex Cloud.
- Права на создание VPC, Compute, Object Storage.
- Сервисный аккаунт с ролями `editor` + `storage.editor` (создаётся в `bootstrap`).

### 3. Переменные окружения

```bash
# Для основного проекта
export YC_SERVICE_ACCOUNT_KEY_FILE="/путь/к/key.json"
export YC_CLOUD_ID="<cloud-id>"
export YC_FOLDER_ID="<folder-id>"

# Для S3-бэкенда (значения из bootstrap)
export AWS_ACCESS_KEY_ID="<access-key>"
export AWS_SECRET_ACCESS_KEY="<secret-key>"

# Для GitLab Runner (staging, prod)
export TF_VAR_gitlab_token='{"staging": "glrt-xxxx", "prod": "glrt-xxxx"}'
```

---

## 🚀 Быстрый старт

### Шаг 1. Bootstrap (один раз)

Создаёт сервисный аккаунт, S3-бакет для Terraform state, Container Registry и ключи доступа:

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# Отредактируйте terraform.tfvars
terraform init
terraform apply
```

Сохраните `access_key`, `secret_key`, `docker_access_key`, `docker_secret_key`, `registry_url`.

📖 Подробнее: [bootstrap.md](./bootstrap.md)

### Шаг 2. Настройка окружения

```bash
cd infrastructure
cp environments/staging/terraform.tfvars.example environments/staging/terraform.tfvars
# Отредактируйте terraform.tfvars
```

### Шаг 3. Деплой инфраструктуры

```bash
# Staging
./scripts/apply.sh staging

# Prod
./scripts/apply.sh prod
```

Скрипт `apply.sh`:
1. Выбирает/создаёт Terraform workspace.
2. Запускает `terraform init`.
3. Проверяет формат и синтаксис.
4. Запускает `terraform plan` и `terraform apply`.

### Шаг 4. Доступ к кластеру

```bash
# Получить kubeconfig
yc managed-kubernetes cluster get-credentials \
  --name staging-managed-k8s \
  --external --force

kubectl get nodes
```

Имя кластера — `<env>-managed-k8s`. Узнать точно:

```bash
terraform output -raw cluster_name
```

---

## 📋 Управление окружениями

### Workspaces

Проект использует **Terraform Workspaces**:

| Workspace | Назначение |
|---|---|
| `staging` | Pre-production |
| `prod` | Production |

Работа с workspace:

```bash
terraform workspace show
terraform workspace select staging
terraform workspace new prod
```

### Параметры окружений

Задаются в `variables.tf` (значения по умолчанию) и переопределяются в `environments/<env>/terraform.tfvars`:

| Параметр | staging | prod |
|---|---|---|
| `worker_count` | 2 | 3 |
| `vpc_cidr` | `10.1.0.0/16` | `10.2.0.0/16` |
| `subnet_cidrs` | 2 подсети | 3 подсети |
| `zones` | a, b | a, b, c |
| GitLab Runner | ✅ | ✅ |
| `pod_cidr` | `10.112.0.0/16` | `10.112.0.0/16` |
| `service_cidr` | `10.96.0.0/16` | `10.96.0.0/16` |

> **Важно:** `pod_cidr` и `service_cidr` **должны совпадать** с реальными диапазонами кластера Yandex Cloud. Если они разойдутся — SG не пропустит pod-to-pod и pod-to-service трафик, что выльется в проблемы с DNS, CoreDNS и egress.

---

## 🔧 Команды

| Команда | Описание |
|---|---|
| `./scripts/apply.sh staging` | Развернуть/обновить staging |
| `./scripts/apply.sh prod` | Развернуть/обновить prod |
| `terraform plan` | Просмотр планируемых изменений |
| `terraform apply` | Применение изменений |
| `terraform destroy` | Удаление инфраструктуры |
| `terraform fmt -recursive` | Форматирование кода |
| `terraform validate` | Проверка синтаксиса |
| `terraform output` | Все выходные значения |
| `terraform output -raw <name>` | Одно значение |
| `terraform state list` | Список ресурсов в state |

---

## 📤 Полезные outputs

```bash
# ID кластера
terraform output -raw cluster_id

# Endpoint Kubernetes API
terraform output -raw cluster_endpoint

# Команда для получения kubeconfig
terraform output -raw get_kubeconfig_command

# ID Security Group для Ingress LB (нужен для Helm-чарта)
terraform output -raw ingress_lb_security_group_id

# IP GitLab Runner (только staging/prod)
terraform output -raw gitlab_runner_ip
```

`ingress_lb_security_group_id` особенно важен — его надо подставить в Helm-чарт `momo-store`:

```yaml
ingress-nginx:
  controller:
    service:
      annotations:
        yandex.cloud/security-group-ids: "<ingress_lb_security_group_id>"
```

---

## 🔒 Безопасность

### Секреты

- Не коммитить: `terraform.tfvars`, `key.json`, `keys.json`, `outputs.json`, `*.tfstate`, `*.tfstate.backup`.
- Секреты — только через переменные окружения (`YC_*`, `AWS_*`, `TF_VAR_*`).
- Для CI/CD — защищённые переменные GitLab.

### Доступы

- В учебном проекте `ssh_allowed_cidrs` = `0.0.0.0/0`. Для production ограничьте конкретными IP.
- `api_allowed_cidrs` для K8s API — тоже стоит ограничить в prod.
- `master.public_ip = true` даёт публичный endpoint API; в prod рассмотрите VPN/bastion.

### Terraform state

- State хранится в S3 (`nameless-terraform-state-bucket`).
- Включено версионирование и lifecycle (удаление старых версий через 30 дней).
- Префикс `infrastructure/<workspace>/terraform.tfstate` — каждый workspace в своём файле.

---

## 📚 Ссылки и документация

### Внутренняя документация

- [Bootstrap](./bootstrap.md) — сервисный аккаунт, S3, Container Registry
- [Networking](./networking.md) — VPC, подсети, NAT, security groups
- [Kubernetes Cluster](./kubernetes-cluster.md) — managed K8s
- [GitLab Runner](./gitlab-runner.md) — установка раннера

### Внешние ресурсы

- [Terraform Yandex Cloud Provider](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs)
- [Yandex Cloud документация](https://cloud.yandex.ru/docs)
- [Kubernetes документация](https://kubernetes.io/docs/)
- [GitLab Runner документация](https://docs.gitlab.com/runner/)