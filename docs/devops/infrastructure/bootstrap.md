# Bootstrap: настройка S3-бакета и Container Registry

## 📋 Описание

Bootstrap-модуль создаёт **первичную инфраструктуру** для проекта Momo Store в Yandex Cloud:

- сервисный аккаунт с правами на Object Storage и Container Registry;
- S3-бакет для хранения **Terraform state**;
- Container Registry для Docker-образов;
- статические и авторизованные ключи доступа.

**Важно:** bootstrap выполняется **один раз** для всего проекта. Все дальнейшие окружения (`dev`, `staging`, `prod`) используют созданные здесь ресурсы.

---

## 🎯 Что будет создано

| Ресурс | Terraform resource | Назначение |
|---|---|---|
| Сервисный аккаунт | `yandex_iam_service_account.state_sa` | Для Terraform и Container Registry |
| Роль `storage.editor` | `yandex_resourcemanager_folder_iam_member.storage_editor` | Доступ к Object Storage |
| Роль `container-registry.editor` | `yandex_resourcemanager_folder_iam_member.container_registry_editor` | Доступ к Container Registry |
| S3-бакет | `yandex_storage_bucket.terraform_state` | Хранение terraform state |
| Container Registry | `yandex_container_registry.main` | Хранение Docker-образов |
| Static access key (S3) | `yandex_iam_service_account_static_access_key.state_sa_key` | Для S3-бэкенда Terraform |
| Static access key (Docker) | `yandex_iam_service_account_static_access_key.docker_key` | Для push/pull образов |
| Authorized key | `yandex_iam_service_account_key.terraform_sa_key` | Для Terraform-провайдера |

**Важно:** bootstrap **не создаёт** бакет для статики фронтенда - он создаётся отдельно и подключается к frontend через Helm-чарт (`values-*.yaml` → `frontend.s3.bucket`).

---

## 📁 Структура модуля

```
bootstrap/
├── main.tf                     # Ресурсы
├── variables.tf                # Входные переменные
├── outputs.tf                  # Выходные значения
├── provider.tf                 # Провайдер Yandex Cloud
├── terraform.tfvars.example    # Пример переменных
└── terraform.tfvars            # Локальные значения (НЕ в Git)
```

---

## 📋 Предварительные требования

### 1. Установленное ПО

| Инструмент | Версия | Назначение |
|---|---|---|
| Terraform | ≥ 1.5.0 | Управление инфраструктурой |
| Yandex Cloud CLI | последняя | Взаимодействие с облаком |
| Docker | последняя | Для работы с Container Registry |
| Git | последняя | Контроль версий |

### 2. Доступы в Yandex Cloud

- Аккаунт в Yandex Cloud.
- Роль `editor` или `admin` в каталоге.
- OAuth-токен (`yc init`).

### 3. Переменные окружения

```bash
export YC_TOKEN="<oauth-token>"
export YC_CLOUD_ID="<cloud-id>"
export YC_FOLDER_ID="<folder-id>"
```

Узнать `cloud_id` и `folder_id`:

```bash
yc config list
```

---

## 🔧 Входные переменные (`variables.tf`)

| Переменная | Тип | По умолчанию | Описание |
|---|---|---|---|
| `cloud_id` | string | - | ID облака |
| `folder_id` | string | - | ID каталога |
| `bucket_name` | string | `my-terraform-state-bucket` | Имя S3-бакета для state |
| `registry_name` | string | `momo-store-registry` | Имя Container Registry |
| `service_account_name` | string | `terraform-sa` | Имя сервисного аккаунта |
| `zone` | string | `ru-central1-a` | Зона доступности |

---

## 🚀 Пошаговая инструкция

### Шаг 1. Перейти в каталог bootstrap

```bash
cd infrastructure/bootstrap
```

### Шаг 2. Создать `terraform.tfvars`

```bash
cp terraform.tfvars.example terraform.tfvars
```

Отредактировать под свой проект:

```hcl
cloud_id             = "b1gxxxxxxxxxxxxxxxxxxx"
folder_id            = "b1gxxxxxxxxxxxxxxxxxxx"
bucket_name          = "momo-store-terraform-state"
registry_name        = "momo-store-registry"
service_account_name = "terraform-sa"
zone                 = "ru-central1-a"
```

### Шаг 3. Инициализировать Terraform

```bash
terraform init
```

### Шаг 4. Посмотреть план

```bash
terraform plan
```

Убедиться, что создаются только ожидаемые ресурсы.

### Шаг 5. Применить

```bash
terraform apply
```

Подтвердить `yes`. Terraform создаст сервисный аккаунт, роли, бакет, registry и ключи.

### Шаг 6. Получить выходные значения

```bash
terraform output
```

Сохранить sensitive-значения в надёжное место (не в Git):

```bash
terraform output -json > outputs.json
```

### Шаг 7. Настроить Docker для Container Registry

```bash
yc container registry configure-docker
```

Это добавит в `~/.docker/config.json` credential helper, чтобы `docker push` и `docker pull` работали без явной аутентификации.

---

## 📤 Выходные значения (`outputs.tf`)

| Output | Sensitive | Описание |
|---|---|---|
| `bucket_name` | нет | Имя S3-бакета для state |
| `registry_id` | нет | ID Container Registry |
| `registry_name` | нет | Имя Container Registry |
| `registry_url` | нет | URL вида `cr.yandex/<id>` |
| `service_account_id` | нет | ID сервисного аккаунта |
| `access_key` | **да** | Access Key для S3 |
| `secret_key` | **да** | Secret Key для S3 |
| `docker_access_key` | **да** | Access Key для Docker |
| `docker_secret_key` | **да** | Secret Key для Docker |

Получить конкретное значение:

```bash
terraform output -raw access_key
terraform output -raw secret_key
terraform output -raw docker_access_key
terraform output -raw docker_secret_key
terraform output -raw registry_url
```

---

## 🔑 Использование ключей

### Для S3-бэкенда Terraform (в `backend.tf` корневого модуля)

Из `outputs.tf` bootstrap:

- `access_key` → `AWS_ACCESS_KEY_ID`
- `secret_key` → `AWS_SECRET_ACCESS_KEY`

Прописать в `~/.aws/credentials` или переменных окружения:

```bash
export AWS_ACCESS_KEY_ID="<access_key>"
export AWS_SECRET_ACCESS_KEY="<secret_key>"
```

### Для `imagePullSecrets` в Kubernetes

Используйте `docker_access_key` / `docker_secret_key` для создания secret:

```bash
kubectl create secret docker-registry ycr-secret \
  --docker-server=cr.yandex \
  --docker-username=json_key \
  --docker-password="$(terraform output -raw docker_secret_key)" \
  -n default
```

### Для Terraform-провайдера

Создан `yandex_iam_service_account_key.terraform_sa_key`. Его содержимое можно использовать как `key.json` для провайдера:

```hcl
provider "yandex" {
  service_account_key_file = "key.json"
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
}
```

Создать `key.json`:

```bash
yc iam key create \
  --service-account-id "$(terraform output -raw service_account_id)" \
  --output key.json
```

---

## ✅ Проверка результата

1. **Object Storage** → бакет `<bucket_name>` создан.
2. **Container Registry** → реестр `<registry_name>` создан.
3. **IAM** → сервисный аккаунт `<service_account_name>` имеет роли:
   - `storage.editor`
   - `container-registry.editor`
4. **Ключи** доступны через `terraform output`.

Проверка через CLI:

```bash
# Бакет
yc storage bucket list

# Registry
yc container registry list

# Сервисный аккаунт и роли
yc iam service-account get --name terraform-sa
yc resource-manager folder list-access-bindings <folder-id>
```

---

## 🧹 Удаление

```bash
terraform destroy
```

**Внимание:** удалит сервисный аккаунт, бакет с Terraform state, Container Registry **и все образы в нём**.  
Если state-бакет используется другими окружениями - **не запускать destroy**, пока они не удалены.

---

## ❗ Важные замечания

- **Запускается один раз** для всего проекта.
- **Не коммитить:** `terraform.tfvars`, `key.json`, `keys.json`, `outputs.json`, `terraform.tfstate`, `terraform.tfstate.backup`. Добавьте их в `.gitignore`.
- **Имя бакета** должно быть глобально уникальным в Yandex Cloud.
- **Ключи sensitive** - обращаться как с паролями. Не логировать, не выводить в CI в открытом виде.
- **Terraform state** bootstrap-модуля хранится **локально** (в папке `bootstrap/`). Это единственный state без S3-бэкенда - потому что бакет для state как раз и создаётся здесь.
- **Container Registry** используется и для Docker-образов, и (при необходимости) для Helm-чартов.

---

## 🧱 Что дальше

После bootstrap можно разворачивать основную инфраструктуру (`infrastructure/`):

- [Networking](./networking.md) - VPC, подсети, security groups.
- [Kubernetes Cluster](./kubernetes-cluster.md) - управляемый кластер.
- [GitLab Runner](./gitlab-runner.md) - runner для CI/CD.

Для каждого окружения - свой workspace Terraform и свой `terraform.tfvars` в `environments/<env>/`.
