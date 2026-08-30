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
# Ожидание завершения user-data скрипта
# ============================================================================

resource "null_resource" "wait_for_cloud_init" {
  depends_on = [yandex_compute_instance.runner]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    agent       = true
    host        = yandex_compute_instance.runner.network_interface.0.nat_ip_address
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo '⏳ Waiting for cloud-init to finish...'",
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo '⏳ Still waiting...'; sleep 10; done",
      "echo '✅ Cloud-init finished'",
      "echo '📋 Checking GitLab Runner status...'",
      "sudo docker ps | grep gitlab-runner || echo '⚠️ GitLab Runner container not running'",
      "sudo docker exec gitlab-runner gitlab-runner list 2>/dev/null || echo '⚠️ GitLab Runner not registered'"
    ]
  }
}