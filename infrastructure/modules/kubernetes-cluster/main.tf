# modules/kubernetes-cluster/main.tf

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
# Control Plane нода
# ============================================================================

resource "yandex_compute_instance" "control_plane" {
  name        = "${var.environment}-control-plane"
  description = "Kubernetes control-plane node for ${var.environment}"
  hostname    = "control-plane"

  zone = var.zones[0]

  platform_id = "standard-v3"

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      type     = "network-hdd"
      size     = var.control_plane_disk_size
    }
  }

  network_interface {
    subnet_id          = var.subnet_ids[0]
    nat                = true
    security_group_ids = [var.control_plane_security_group_id]
  }

  metadata = {
    ssh-keys = "ubuntu:${var.ssh_public_key}"

    user-data = templatefile("${path.module}/scripts/control-plane-setup.sh", {
      kubernetes_version   = var.kubernetes_version
      pod_network_cidr     = var.pod_network_cidr
      service_network_cidr = var.service_network_cidr
      cluster_name         = var.cluster_name
      environment          = var.environment
    })
  }

  labels = merge(
    {
      environment = var.environment
      role        = "control-plane"
      managed_by  = "terraform"
      cluster     = var.cluster_name
    },
    var.tags
  )

  lifecycle {
    ignore_changes = [
      metadata["user-data"],
    ]
  }
}

# ============================================================================
# Получение join-команды с control-plane
# ============================================================================

resource "null_resource" "get_join_command" {
  depends_on = [yandex_compute_instance.control_plane]

  provisioner "local-exec" {
    command = <<-EOT
      echo "⏳ Waiting for control-plane to be ready..."
      sleep 60
      
      CONTROL_PLANE_IP="${yandex_compute_instance.control_plane.network_interface.0.nat_ip_address}"
      echo "ℹ️ Control-plane IP: $CONTROL_PLANE_IP"
      
      # Проверка SSH-доступа
      echo "🔍 Checking SSH access..."
      ssh -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} ubuntu@$CONTROL_PLANE_IP "echo 'SSH OK'" 2>&1
      
      # Читаем /tmp/join-command.txt
      for i in 1 2 3 4 5 6 7 8; do
        echo "Attempt $i: Getting join command from control-plane..."
        ssh -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} ubuntu@$CONTROL_PLANE_IP "sudo cat /tmp/join-command.txt" > ./join-command.txt 2>/dev/null
        if [ -s ./join-command.txt ]; then
          echo "✅ Join command received!"
          cat ./join-command.txt
          break
        fi
        echo "⚠️ Failed attempt $i, waiting 10 seconds..."
        sleep 30
      done
      
      if [ ! -s ./join-command.txt ]; then
        echo "❌ Failed to get join command after 10 attempts"
        echo "📋 Manual join command (run on control-plane):"
        echo "  sudo cat /tmp/join-command.txt"
        exit 1
      fi
    EOT
  }
}

# ============================================================================
# Чтение join-команды из локального файла
# ============================================================================

data "local_file" "join_command" {
  depends_on = [null_resource.get_join_command]
  filename   = "./join-command.txt"
}

# ============================================================================
# Worker ноды
# ============================================================================

resource "yandex_compute_instance" "workers" {
  count = var.worker_count

  name        = "${var.environment}-worker-${count.index + 1}"
  description = "Kubernetes worker node ${count.index + 1} for ${var.environment}"
  hostname    = "worker-${count.index + 1}"

  zone = var.zones[count.index % length(var.zones)]

  platform_id = "standard-v3"

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 100
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      type     = "network-hdd"
      size     = var.worker_disk_size
    }
  }

  network_interface {
    subnet_id          = var.subnet_ids[count.index % length(var.subnet_ids)]
    nat                = true
    security_group_ids = [var.workers_security_group_id]
  }

  metadata = {
    ssh-keys = "ubuntu:${var.ssh_public_key}"

    user-data = templatefile("${path.module}/scripts/worker-setup.sh", {
      kubernetes_version = var.kubernetes_version
      control_plane_ip   = yandex_compute_instance.control_plane.network_interface.0.ip_address
      environment        = var.environment
      join_command       = data.local_file.join_command.content
    })
  }

  labels = merge(
    {
      environment = var.environment
      role        = "worker"
      managed_by  = "terraform"
      cluster     = var.cluster_name
    },
    var.tags
  )

  depends_on = [
    yandex_compute_instance.control_plane,
    null_resource.get_join_command
  ]

  lifecycle {
    ignore_changes = [
      metadata["user-data"],
    ]
  }
}

# ============================================================================
# Выходные данные для получения kubeconfig
# ============================================================================

locals {
  control_plane_ip     = yandex_compute_instance.control_plane.network_interface.0.ip_address
  control_plane_nat_ip = yandex_compute_instance.control_plane.network_interface.0.nat_ip_address
  worker_ips           = yandex_compute_instance.workers[*].network_interface.0.ip_address
  worker_nat_ips       = yandex_compute_instance.workers[*].network_interface.0.nat_ip_address
}