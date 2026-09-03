# Bootstrap: Настройка S3-бакета для Terraform State

## 📋 Описание
Этот документ описывает процесс первичной настройки инфраструктуры для хранения Terraform state-файлов в Yandex Object Storage.

**Важно:** Этот процесс выполняется **ОДИН РАЗ** для всего проекта.

## 🎯 Что будет создано
- S3-бакет в Yandex Object Storage
- Сервисный аккаунт с правами на бакет
- Статические ключи доступа для сервисного аккаунта

## 📋 Предварительные требования

### 1. Установленное ПО
- Terraform >= 1.5.0 ([инструкция по установке](https://developer.hashicorp.com/terraform/downloads))
- Yandex Cloud CLI ([инструкция](https://cloud.yandex.ru/docs/cli/quickstart))
- Git

### 2. Доступы в Yandex Cloud
- OAuth-токен ([получить здесь](https://oauth.yandex.ru/))
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

Создайте файл `terraform.tfvars` на основе шаблона:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Отредактируйте `terraform.tfvars`, вставив реальные значения.

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

### Шаг 5: Получите ключи доступа

```bash
# Вывод всех выходных данных
terraform output

# Сохраните ключи в безопасное место
terraform output -json > keys.json

# Или отдельно:
terraform output access_key
terraform output secret_key
```

### Шаг 6: Сохраните ключи доступа

Важно! Сохраните полученные access_key и secret_key в надежном месте (например, в менеджере паролей или в защищенном файле). Они понадобятся для настройки backend.tf в основном проекте.

## ✅ Проверка результата

1. Перейдите в консоль Yandex Cloud → Object Storage
2. Убедитесь, что бакет с указанным именем создан
3. Проверьте, что версионирование включено

## 🧹 Очистка (если нужно удалить)

```bash
# Удаление всех созданных ресурсов
terraform destroy
```

## ❗️ Важные замечания

1. Запустите этот процесс только один раз для всего проекта
2. Не коммитьте terraform.tfvars и keys.json в Git
3. Сохраните ключи доступа - они потребуются для всех последующих окружений
4. Имя бакета должно быть глобально уникальным в Yandex Cloud

## 🔗 Следующие шаги

После успешного создания бакета:

1. Перейдите к настройке основного Terraform-проекта
2. Обновите infrastructure/backend.tf с использованием полученных ключей
3. Разверните инфраструктуру для окружения dev