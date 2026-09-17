# modules/gitlab-runner/main.tf

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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.0"
    }
  }
}

# ============================================================================
# Данные об образе
# ============================================================================

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

# ============================================================================
# Виртуальная машина для GitLab Runner
# ============================================================================

resource "yandex_compute_instance" "runner" {
  name        = "${var.environment}-runner"
  hostname    = "${var.environment}-runner"
  platform_id = "standard-v3"

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = var.disk_size
    }
  }

  network_interface {
    subnet_id          = var.subnet_id
    nat                = true
    security_group_ids = var.security_group_ids
  }

  metadata = {
    ssh-keys = "ubuntu:${var.ssh_public_key}"
    user-data = templatefile("${path.module}/scripts/install-runner.sh", {
      environment  = var.environment
      gitlab_url   = var.gitlab_url
      gitlab_token = var.gitlab_token
    })
  }

  labels = var.tags
}

# ============================================================================
# Принудительная задержка перед проверкой
# ============================================================================

resource "time_sleep" "wait_for_runner" {
  depends_on      = [yandex_compute_instance.runner]
  create_duration = "90s"
}

# ============================================================================
# Ожидание завершения user-data скрипта
# ============================================================================

resource "null_resource" "wait_for_cloud_init" {
  depends_on = [time_sleep.wait_for_runner]

  connection {
    type    = "ssh"
    user    = "ubuntu"
    agent   = true
    host    = yandex_compute_instance.runner.network_interface.0.nat_ip_address
    timeout = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '⏳ Waiting for cloud-init to finish (max 5 minutes)...'",
      "for i in $(seq 1 30); do",
      "  if [ -f /var/lib/cloud/instance/boot-finished ]; then",
      "    echo '✅ Cloud-init finished'",
      "    break",
      "  fi",
      "  echo \"⏳ Attempt $i/30: Still waiting...\"",
      "  sleep 10",
      "done",
      "if [ ! -f /var/lib/cloud/instance/boot-finished ]; then",
      "  echo '❌ Cloud-init did not finish within 5 minutes'",
      "  exit 1",
      "fi",
      "echo '📋 Checking GitLab Runner status...'",
      "sudo docker ps | grep gitlab-runner || echo '⚠️ GitLab Runner container not running'",
      "sudo docker exec gitlab-runner gitlab-runner list 2>/dev/null || echo '⚠️ GitLab Runner not registered'"
    ]
  }
}