# Infrastructure as Code (IaC) для Kubernetes кластера

## 📋 Описание

Проект управляет инфраструктурой для Kubernetes-кластера в Yandex Cloud с использованием **Terraform**. Вся инфраструктура описана как код и разделена по окружениям через **Terraform Workspaces**: `staging`, `prod`.

Модуль `networking` создаёт VPC, подсети, NAT, security groups. Модуль `kubernetes-cluster` разворачивает managed Kubernetes. Модуль `gitlab-runner` - опционально - разворачивает ВМ с GitLab Runner.

После `terraform apply` скрипт `apply.sh` **автоматически** настраивает RBAC в кластере для CI/CD через `setup-ci-rbac.sh` - создаёт ServiceAccount, Role, RoleBinding и долгоживущий токен, а затем прописывает kubeconfig в переменную GitLab.

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
│  │   │                                                         │          │  │
│  │   │  ┌────────────────────────────────────────┐             │          │  │
│  │   │  │ CI/CD RBAC                             │             │          │  │
│  │   │  │  • ServiceAccount: ci-deployer         │             │          │  │
│  │   │  │  • Role + RoleBinding (namespace default)            │          │  │
│  │   │  │  • Secret: ci-deployer-token           │             │          │  │
│  │   │  └────────────────────────────────────────┘             │          │  │
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
│   ├── apply.sh                     # Применение Terraform + настройка RBAC
│   └── setup-ci-rbac.sh             # Настройка RBAC в кластере для GitLab CI
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
| curl | последняя | Для обновления переменных GitLab через API |
| Git | последняя | Контроль версий |

### 2. Доступы в Yandex Cloud

- Аккаунт в Yandex Cloud.
- Права на создание VPC, Compute, Object Storage.
- Сервисный аккаунт с ролями `editor` + `storage.editor` (создаётся в `bootstrap`).

### 3. Доступы в GitLab

- **Personal Access Token** с scope `api` - для автоматического обновления переменной `KUBE_CONFIG_<ENV>`.
- Роль **Maintainer** или **Owner** в проекте - иначе API вернёт `403` при попытке создать/обновить переменную.

### 4. Переменные окружения

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

# Для автоматической настройки RBAC (setup-ci-rbac.sh)
export GITLAB_TOKEN="<gitlab_api_acess_token>"          # Personal Access Token со scope api
export GITLAB_PROJECT_ID="<gitlab_project_id>"          # ID проекта в GitLab
export GITLAB_URL="<gitlab_instance_url>"
```

Если `GITLAB_TOKEN` или `GITLAB_PROJECT_ID` не заданы - `setup-ci-rbac.sh` **не упадёт**, но пропустит обновление переменной GitLab и выведет base64 kubeconfig для ручной вставки.

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

Скрипт `apply.sh` делает **две вещи**:

1. **Terraform apply** - создаёт/обновляет инфраструктуру.
   - Выбирает/создаёт Terraform workspace.
   - Запускает `terraform init`, `fmt`, `validate`, `plan`, `apply`.

2. **Настройка RBAC для CI/CD** (см. `setup-ci-rbac.sh`):
   - Подключается к кластеру через `yc managed-kubernetes cluster get-credentials`.
   - Создаёт `ServiceAccount`, `Role`, `RoleBinding` в namespace `default`.
   - Создаёт долгоживущий токен через `Secret` типа `service-account-token`.
   - Собирает kubeconfig с токеном.
   - Обновляет переменную `KUBE_CONFIG_<ENV>` в GitLab через API.

### Шаг 4. Доступ к кластеру

```bash
# Получить kubeconfig
yc managed-kubernetes cluster get-credentials \
  --name staging-managed-k8s \
  --external --force

kubectl get nodes
```

Имя кластера - `<env>-managed-k8s`. Узнать точно:

```bash
terraform output -raw cluster_name
```

---

## 🔐 CI/CD RBAC

Скрипт `setup-ci-rbac.sh` настраивает **минимально необходимые права** для GitLab CI. После его выполнения CI-раннер может деплоить приложения в namespace `default`, но **не имеет доступа** к другим namespace или к cluster-wide ресурсам.

### Что создаётся

| Ресурс | Назначение |
|---|---|
| `ServiceAccount/ci-deployer` (namespace `default`) | Идентичность CI в кластере |
| `Role/ci-deployer` (namespace `default`) | Права на деплой приложений |
| `RoleBinding/ci-deployer` | Связка SA ↔ Role |
| `Secret/ci-deployer-token` | Долгоживущий токен SA |

### Права Role

| Группа | Ресурсы | Verbs |
|---|---|---|
| `""` (core) | configmaps, secrets, services, serviceaccounts, PVC | get, list, watch, create, update, patch, delete |
| `""` (core) | pods, pods/log, pods/exec, endpoints, events, replicasets | get, list, watch |
| `""` (core) | namespaces | get, list, watch |
| `apps` | deployments, replicasets, statefulsets, daemonsets | полный |
| `batch` | jobs, cronjobs | полный |
| `networking.k8s.io` | ingresses | полный |
| `autoscaling` | horizontalpodautoscalers | полный |

**Чего нет и не должно быть:** доступа к `nodes`, `clusterroles`, `clusterrolebindings`, `persistentvolumes`, ресурсам в других namespace.

### Что скрипт обновляет в GitLab

Переменную `KUBE_CONFIG_STAGING` (или `KUBE_CONFIG_PROD`). Она содержит **base64 от kubeconfig** с долгоживущим токеном. В CI деплой-джоба декодирует её и использует для `kubectl` / `helm`.

Токен **не истекает**, пока существует Secret `ci-deployer-token`. Не нужно регулярно перевыпускать.

### Запуск вручную

Если нужно настроить RBAC без `terraform apply` (например, после пересоздания кластера или для отладки):

```bash
cd infrastructure
export GITLAB_TOKEN="<gitlab_api_acess_token>"
export GITLAB_PROJECT_ID="<gitlab_project_id>"
export GITLAB_URL="<gitlab_instance_url>"

./scripts/setup-ci-rbac.sh staging
```

Скрипт идемпотентен - повторный запуск не сломает существующие ресурсы (`kubectl apply` перезапишет их тем же содержимым).

### Проверка после настройки

```bash
# В кластере
kubectl get sa,role,rolebinding,secret -n default | grep ci-deployer

# Kubeconfig работает
KUBECONFIG=/tmp/kubeconfig-ci kubectl get pods -n default

# RBAC ограничен
KUBECONFIG=/tmp/kubeconfig-ci kubectl get nodes
# Ожидаем: Forbidden - прав на nodes нет
```

### Если GitLab API возвращает 403

Скрипт не смог обновить переменную. Причины:

1. **`GITLAB_TOKEN` без scope `api`.** Проверьте в GitLab → User Settings → Access Tokens.
2. **Роль в проекте ниже Maintainer.** Проверьте в GitLab → проект → Members.
3. **Переменная защищена (Protected), а ветка не protected.** В скрипте стоит `protected=false` при создании, но при обновлении - флаг не меняется. Проверьте вручную в Settings → CI/CD → Variables.

Если 403 всё равно - скрипт **выведет base64 kubeconfig**. Скопируйте его вручную в переменную GitLab.

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

> **Важно:** `pod_cidr` и `service_cidr` **должны совпадать** с реальными диапазонами кластера Yandex Cloud. Если они разойдутся - SG не пропустит pod-to-pod и pod-to-service трафик, что выльется в проблемы с DNS, CoreDNS и egress.

---

## 🔧 Команды

| Команда | Описание |
|---|---|
| `./scripts/apply.sh staging` | Развернуть/обновить staging + настроить RBAC |
| `./scripts/apply.sh prod` | Развернуть/обновить prod + настроить RBAC |
| `./scripts/setup-ci-rbac.sh staging` | Только настроить RBAC (без Terraform) |
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

`ingress_lb_security_group_id` особенно важен - его надо подставить в Helm-чарт `momo-store`:

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

- Не коммитить: `terraform.tfvars`, `key.json`, `keys.json`, `outputs.json`, `*.tfstate`, `*.tfstate.backup`, `kubeconfig-*`.
- Секреты - только через переменные окружения (`YC_*`, `AWS_*`, `TF_VAR_*`, `GITLAB_*`).
- Для CI/CD - защищённые переменные GitLab.

### Доступы

- В учебном проекте `ssh_allowed_cidrs` = `0.0.0.0/0`. Для production ограничьте конкретными IP.
- `api_allowed_cidrs` для K8s API - тоже стоит ограничить в prod.
- `master.public_ip = true` даёт публичный endpoint API; в prod рассмотрите VPN/bastion.
- **CI-токен ограничен namespace `default`** - если утечёт, злоумышленник получит доступ только к этому namespace, не к кластеру целиком.

### Terraform state

- State хранится в S3 (`nameless-terraform-state-bucket`).
- Включено версионирование и lifecycle (удаление старых версий через 30 дней).
- Префикс `infrastructure/<workspace>/terraform.tfstate` - каждый workspace в своём файле.

---

## 📚 Ссылки и документация

### Внутренняя документация

- [Bootstrap](./bootstrap.md) - сервисный аккаунт, S3, Container Registry
- [Networking](./networking.md) - VPC, подсети, NAT, security groups
- [Kubernetes Cluster](./kubernetes-cluster.md) - managed K8s
- [GitLab Runner](./gitlab-runner.md) - установка раннера

### Внешние ресурсы

- [Terraform Yandex Cloud Provider](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs)
- [Yandex Cloud документация](https://cloud.yandex.ru/docs)
- [Kubernetes документация](https://kubernetes.io/docs/)
- [GitLab Runner документация](https://docs.gitlab.com/runner/)
- [GitLab API: project variables](https://docs.gitlab.com/ee/api/project_level_variables.html)