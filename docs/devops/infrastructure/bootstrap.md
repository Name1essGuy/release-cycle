# Bootstrap: Настройка S3-бакета и Container Registry

## 📋 Описание
Этот документ описывает процесс первичной настройки инфраструктуры для хранения Terraform state-файлов в Yandex Object Storage и создания Container Registry для Docker-образов.

**Важно:** Этот процесс выполняется **ОДИН РАЗ** для всего проекта.

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

### 3. Права
- Роль `editor` или `admin` в Yandex Cloud

## 🚀 Пошаговая инструкция

### Шаг 1: Клонируйте репозиторий
```bash
git clone <your-repo-url>
cd momo-store/infrastructure/bootstrap
```

### Шаг 2: Настройте переменные окружения

Создайте файл terraform.tfvars на основе шаблона:

```bash
cp terraform.tfvars.example terraform.tfvars
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

### Шаг 3: Установите переменные окружения для Yandex Cloud

```bash
# Для Linux/macOS
export YC_TOKEN="<your-oauth-token>"
export YC_CLOUD_ID="<your-cloud-id>"
export YC_FOLDER_ID="<your-folder-id>"

# Для Windows (PowerShell)
$env:YC_TOKEN = "<your-oauth-token>"
$env:YC_CLOUD_ID = "<your-cloud-id>"
$env:YC_FOLDER_ID = "<your-folder-id>"
```


### Шаг 4: Инициализируйте и примените Terraform

```bash
# Инициализация (загружает провайдеры)
terraform init

# Проверка плана (что будет создано)
terraform plan

# Создание ресурсов
terraform apply

# Подтвердите действие, введя "yes"
```

### Шаг 5: Получите выходные данные

```bash
# Вывод всех выходных данных
terraform output

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
# Удаление всех созданных ресурсов
terraform destroy
```

## ❗️ Важные замечания

- Запустите этот процесс только один раз для всего проекта
- Не коммитьте terraform.tfvars, key.json и outputs.json в Git
- Сохраните ключи доступа — они потребуются для всех последующих окружений
- Имя бакета должно быть глобально уникальным в Yandex Cloud
- Container Registry используется для хранения Docker-образов и Helm-чартов