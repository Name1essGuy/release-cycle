# infrastructure/provider.tf

terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.100.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3.0"
    }
  }
}

provider "yandex" {
  # Переменные окружения:
  # export YC_SERVICE_ACCOUNT_KEY_FILE="<путь_к_key.json>"
  # export YC_CLOUD_ID="<cloud_id>"
  # export YC_FOLDER_ID="<folder_id>"

  zone = "ru-central1-a"
}