# infrastructure/backend.tf

terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://storage.yandexcloud.net"
    }
    bucket               = "nameless-terraform-state-bucket"
    region               = "ru-central1"
    key                  = "terraform.tfstate"
    workspace_key_prefix = "infrastructure"

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true

    # Переменные окружения (из bootstrap):
    # export AWS_ACCESS_KEY_ID="..."
    # export AWS_SECRET_ACCESS_KEY="..."
  }
}
