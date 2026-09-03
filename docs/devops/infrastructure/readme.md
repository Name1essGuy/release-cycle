# Infrastructure as Code (IaC) для Kubernetes кластера

## 📋 Описание

Этот проект управляет инфраструктурой для Kubernetes кластера в Yandex Cloud с использованием **Terraform**. Вся инфраструктура описана как код и разделена на окружения: `dev`, `staging`, `prod`.

---

## 🏗️ Архитектура


```markdown
┌─────────────────────────────────────────────────────────────────────────────┐
│ Yandex Cloud                                                                │
│ ┌───────────────────────────────────────────────────────────────────────┐   │
│ │ VPC (Virtual Private Cloud)                                           │   │
│ │ ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                  │   │
│ │ │   Subnet A   │  │  Subnet B    │  │ Subnet C     │                  │   │
│ │ │ ru-central1-a│  │ ru-central1-b│  │ ru-central1-c│                  │   │
│ │ └──────┬───────┘  └──────┬───────┘  └──────┬───────┘                  │   │
│ │        │                 │                 │                          │   │
│ │ ┌──────▼─────────────────▼─────────────────▼──────┐                   │   │
│ │ │                  Security Groups                │                   │   │
│ │ │   • Control Plane • Workers • GitLab Runner     │                   │   │
│ │ └──────────────────────┬──────────────────────────┘                   │   │
│ │                        │                                              │   │
│ │ ┌──────────────────────▼───────────────────────────┐                  │   │
│ │ │ Kubernetes Cluster                               │                  │   │
│ │ │ ┌────────────────────────────────────────────┐   │                  │   │
│ │ │ │          Control Plane (master)            │   │                  │   │
│ │ │ │ • kube-apiserver                           │   │                  │   │
│ │ │ │ • etcd                                     │   │                  │   │
│ │ │ │ • kube-scheduler                           │   │                  │   │
│ │ │ │ • kube-controller-manager                  │   │                  │   │
│ │ │ └────────────────────────────────────────────┘   │                  │   │
│ │ │ ┌──────────────┐ ┌──────────────┐                │                  │   │
│ │ │ │ Worker 1     │ │ Worker 2     │ ...            │                  │   │
│ │ │ │ • containerd │ │ • containerd │                │                  │   │
│ │ │ │ • kubelet │ │ • kubelet │ │ │ │                │                  │   │
│ │ │ │ • kube-proxy│ │ • kube-proxy│ │                │                  │   │
│ │ │ └──────────────┘ └──────────────┘                │                  │   │
│ │ └──────────────────────────────────────────────────┘                  │   │
│ │                                                                       │   │
│ │ ┌──────────────────────────────────────────────────┐                  │   │
│ │ │           GitLab Runner (staging/prod)           │                  │   │
│ │ │ • Docker executor                                │                  │   │
│ │ │ • kubectl, helm, yc CLI                          │                  │   │
│ │ └──────────────────────────────────────────────────┘                  │   │
│ └───────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│ ┌───────────────────────────────────────────────────────────────────────┐   │
│ │                     S3 Bucket (Terraform State)                       │   │
│ │ • /infrastructure/dev/terraform.tfstate                               │   │
│ │ • /infrastructure/staging/terraform.tfstate                           │   │
│ │ • /infrastructure/prod/terraform.tfstate                              │   │
│ └───────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📁 Структура проекта

```markdown
infrastructure/
│
├── bootstrap/ # Создание S3-бакета (запускается 1 раз)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
│   
│
├── environments/ # Настройки для окружений
│   ├── dev/
│   │   └── terraform.tfvars.example
│   ├── staging/
│   │   └── terraform.tfvars.example
│   └── prod/
│       └── terraform.tfvars.example
│
├── modules/ # Переиспользуемые модули
│   ├── networking/ # VPC, подсети, security groups
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │  
│   ├── kubernetes-cluster/ # Kubernetes кластер
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── scripts/
│   │       ├── control-plane-setup.sh
│   │       └── worker-setup.sh
│   │   
│   └── gitlab-runner/ # GitLab Runner
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── scripts/
│           └── install-runner.sh
│       
│
├── scripts/ # Вспомогательные скрипты
│   ├── apply.sh # Применение для окружения
│   ├── destroy.sh # Удаление окружения
│   ├── get-kubeconfig.sh # Получение kubeconfig
│   └── setup-env.sh.example # Шаблон переменных окружения
│
├── .gitignore
├── .terraform-version
├── backend.tf # S3 бэкенд для хранения состояния
├── provider.tf # Конфигурация провайдера Yandex Cloud
├── variables.tf # Глобальные переменные
├── main.tf # Точка входа (вызов модулей)
└── outputs.tf # Глобальные выходы 
```

---

## 🔧 Предварительные требования

### 1. Установленное ПО
| Инструмент | Версия | Назначение |
| :--- | :--- | :--- |
| **Terraform** | >= 1.5.0 | Управление инфраструктурой |
| **Yandex Cloud CLI** | последняя | Взаимодействие с Yandex Cloud |
| **kubectl** | >= 1.28 | Управление Kubernetes |
| **Git** | последняя | Контроль версий |

### 2. Доступы в Yandex Cloud
- Аккаунт в Yandex Cloud
- Права на создание ресурсов (VPC, Compute, Object Storage)
- Сервисный аккаунт с ролью `storage.admin` (для bootstrap)
- Сервисный аккаунт с ролью `editor` (для основной инфраструктуры)

### 3. Настройка переменных окружения

```bash
# Для сервисного аккаунта (основной проект)
export YC_SERVICE_ACCOUNT_KEY_FILE="/путь/к/key.json"
export YC_CLOUD_ID="<your-cloud-id>"
export YC_FOLDER_ID="<your-folder-id>"

# Для S3 бэкенда (из bootstrap)
export AWS_ACCESS_KEY_ID="<access-key-from-bootstrap>"
export AWS_SECRET_ACCESS_KEY="<secret-key-from-bootstrap>"

# Для GitLab Runner (для staging/prod)
export TF_VAR_gitlab_token='{"staging": "glrt-xxxxxxxxxxxx", "prod: "glrt-xxxxxxxxxxxx"}'
```

---

## 🚀 Быстрый старт
### Шаг 1: Bootstrap (запускается 1 раз)

Создает S3-бакет для хранения Terraform state:

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# Отредактируйте terraform.tfvars
terraform init
terraform apply
# Сохраните access_key и secret_key
```

📖 Подробнее: [docs/devops/infrastructure/bootstrap.md](./bootstrap.md)

### Шаг 2: Настройка основного проекта

```bash
cd infrastructure

# Создайте terraform.tfvars для нужного окружения
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars
# Отредактируйте файл с параметрами окружения
```

### Шаг 3: Развёртывание инфраструктуры

```bash
# Для dev окружения
./scripts/apply.sh dev

# Для staging окружения
./scripts/apply.sh staging

# Для prod окружения
./scripts/apply.sh prod
```

### Шаг 4: Получение доступа к кластеру

```bash
# Получить kubeconfig для dev
./scripts/get-kubeconfig.sh dev

# Использовать kubectl
export KUBECONFIG=./kubeconfig-dev
kubectl get nodes
kubectl get pods -A
```

---

## 📋 Управление окружениями

### Workspaces

Проект использует **Terraform Workspaces** для разделения окружений:

| Workspace | Окружение       | Назначение                          |
|-----------|-----------------|-------------------------------------|
| dev       | Development     | Разработка и тестирование           |
| staging   | Staging         | Предпродакшен тестирование          |
| prod      | Production      | Боевое окружение                    |

#### Переключение между окружениями:

```bash
# Просмотр текущего workspace
terraform workspace show

# Переключение
terraform workspace select dev

# Создание нового workspace
terraform workspace new staging
```

### Параметры окружений

| Параметр         | dev              | staging          | prod             |
|------------------|------------------|------------------|------------------|
| Worker count     | 1                | 2                | 3                |
| Control Plane    | s2.micro         | s2.medium        | s2.large         |
| Worker           | s2.micro         | s2.medium        | s2.large         |
| GitLab Runner    | ❌ Нет           | ✅ Да            | ✅ Да            |
| VPC CIDR         | 10.0.0.0/16      | 10.1.0.0/16      | 10.2.0.0/16      |
| Subnets          | 2                | 2                | 3                |

## 🔧 Команды для работы

### Основные команды

| Команда                              | Описание                              |
|--------------------------------------|---------------------------------------|
| `./scripts/apply.sh dev`             | Развернуть/обновить dev окружение     |
| `./scripts/destroy.sh dev`           | Удалить dev окружение                 |
| `./scripts/get-kubeconfig.sh dev`    | Получить kubeconfig для dev           |
| `terraform plan`                     | Просмотр планируемых изменений        |
| `terraform apply`                    | Применение изменений                  |
| `terraform destroy`                  | Удаление инфраструктуры               |
| `terraform fmt`                      | Форматирование кода                   |
| `terraform validate`                 | Проверка синтаксиса                   |

### Полезные команды

```bash
# Просмотр всех ресурсов
terraform state list

# Просмотр конкретного ресурса
terraform state show module.kubernetes_cluster.yandex_compute_instance.control_plane[0]

# Получить выходные данные
terraform output

# Получить конкретный выход
terraform output -raw control_plane_nat_ip
```

## 🔒 Безопасность

### Секреты
- Никогда не коммитьте .tfvars файлы и key.json
- Используйте переменные окружения для секретов
- Для CI/CD используйте защищённые переменные GitLab

### Доступы
- Для учебного проекта SSH разрешён со всех IP (0.0.0.0/0)
- В production ограничьте доступы конкретными IP

### State файл
- State файл хранится в S3 с шифрованием
- Включено версионирование для защиты от случайного удаления

## 📚 Ссылки и документация

### Внутренняя документация
- [Bootstrap](./bootstrap.md) — создание S3-бакета
- [Networking](./networking.md) — сеть и security groups
- [Kubernetes Cluster](./kubernetes-cluster.md) — создание кластера
- [GitLab Runner](./gitlab-runner.md) — настройка раннера

### Внешние ресурсы

- [Terraform Yandex Cloud Provider](https://registry.terraform.io/providers/yandex-cloud/yandex/latest/docs)
- [Yandex Cloud документация](https://cloud.yandex.ru/docs)
- [Kubernetes документация](https://kubernetes.io/docs/)
- [GitLab Runner документация](https://docs.gitlab.com/runner/)