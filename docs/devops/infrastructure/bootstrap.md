# Bootstrap: Настройка S3-бакета и Container Registry

## 📋 Описание
Этот документ описывает процесс первичной настройки инфраструктуры для хранения Terraform state-файлов в Yandex Object Storage и создания Container Registry для Docker-образов.

Bootstrap-модуль создаёт **первичную инфраструктуру** для проекта Momo Store в Yandex Cloud:

- сервисный аккаунт с правами на Object Storage и Container Registry;
- S3-бакет для хранения **Terraform state**;
- Container Registry для Docker-образов;
- статические и авторизованные ключи доступа.

**Важно:** bootstrap выполняется **один раз** для всего проекта. Все дальнейшие окружения (`dev`, `staging`, `prod`) используют созданные здесь ресурсы.

---

## 🎯 Что будет создано
- S3-бакет в Yandex Object Storage
- Container Registry для Docker-образов
- Сервисный аккаунт с правами на бакет и реестр
- Статические ключи доступа для сервисного аккаунта
- Авторизованный ключ для Terraform

## 📋 Предварительные требования

### 1. Установленное ПО
- Terraform >= 1.5.0
- Yandex Cloud CLI
- Git
- Docker (для работы с Container Registry)

### 2. Доступы в Yandex Cloud
- OAuth-токен
- Cloud ID и Folder ID (можно получить через `yc config list`)

- Аккаунт в Yandex Cloud.
- Роль `editor` или `admin` в каталоге.
- OAuth-токен (`yc init`).

### 3. Переменные окружения

```bash
export YC_TOKEN="<oauth-token>"
export YC_CLOUD_ID="<cloud-id>"
export YC_FOLDER_ID="<folder-id>"
```

### Шаг 2: Настройте переменные окружения

Создайте файл terraform.tfvars на основе шаблона:

```bash
yc config list
```

Отредактируйте terraform.tfvars:

```hcl
cloud_id              = "b1gxxxxxxxxxxxxxxxxxxx"
folder_id             = "b1gxxxxxxxxxxxxxxxxxxx"
bucket_name           = "my-terraform-state-bucket"
registry_name         = "momo-store-registry"
service_account_name  = "terraform-sa"
zone                  = "ru-central1-a"
```

| Переменная | Тип | По умолчанию | Описание |
|---|---|---|---|
| `cloud_id` | string | — | ID облака |
| `folder_id` | string | — | ID каталога |
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


### Шаг 4: Инициализируйте и примените Terraform

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

### Шаг 5: Получите выходные данные

```bash
terraform output
```

Сохранить sensitive-значения в надёжное место (не в Git):

```bash
terraform output -json > outputs.json
```

# Сохраните в файл
terraform output -json > outputs.json

# Получить URL Container Registry
terraform output registry_url

# Получить Access Key для Docker
terraform output docker_access_key
```

### Шаг 6: Настройте Docker для работы с Container Registry

```bash
# Аутентификация через Yandex Cloud CLI
yc container registry configure-docker

# Или через статический ключ
export DOCKER_ACCESS_KEY=$(terraform output -raw docker_access_key)
export DOCKER_SECRET_KEY=$(terraform output -raw docker_secret_key)
docker login -u json_key --password-stdin cr.yandex <<< "$DOCKER_SECRET_KEY"
```

## 📤 Выходные данные

| Выход | Описание |
|-------|----------|
| `bucket_name` | Имя S3-бакета |
| `registry_url` | URL Container Registry |
| `registry_id` | ID Container Registry |
| `service_account_id` | ID сервисного аккаунта |
| `access_key` | Access Key для S3 (sensitive) |
| `secret_key` | Secret Key для S3 (sensitive) |
| `docker_access_key` | Access Key для Docker (sensitive) |
| `docker_secret_key` | Secret Key для Docker (sensitive) |

## ✅ Проверка результата

1. Перейдите в консоль Yandex Cloud → Object Storage — убедитесь, что бакет создан
2. Перейдите в консоль Yandex Cloud → Container Registry — убедитесь, что реестр создан
3. Проверьте, что сервисный аккаунт имеет роли storage.editor и container-registry.editor

## 🧹 Очистка

```bash
terraform destroy
```

**Внимание:** удалит сервисный аккаунт, бакет с Terraform state, Container Registry **и все образы в нём**.  
Если state-бакет используется другими окружениями — **не запускать destroy**, пока они не удалены.

---

## ❗ Важные замечания

- **Запускается один раз** для всего проекта.
- **Не коммитить:** `terraform.tfvars`, `key.json`, `keys.json`, `outputs.json`, `terraform.tfstate`, `terraform.tfstate.backup`. Добавьте их в `.gitignore`.
- **Имя бакета** должно быть глобально уникальным в Yandex Cloud.
- **Ключи sensitive** — обращаться как с паролями. Не логировать, не выводить в CI в открытом виде.
- **Terraform state** bootstrap-модуля хранится **локально** (в папке `bootstrap/`). Это единственный state без S3-бэкенда — потому что бакет для state как раз и создаётся здесь.
- **Container Registry** используется и для Docker-образов, и (при необходимости) для Helm-чартов.

---

- Запустите этот процесс только один раз для всего проекта
- Не коммитьте terraform.tfvars, key.json и outputs.json в Git
- Сохраните ключи доступа — они потребуются для всех последующих окружений
- Имя бакета должно быть глобально уникальным в Yandex Cloud
- Container Registry используется для хранения Docker-образов и Helm-чартов
