# modules/kubernetes-cluster/main.tf

terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.100.0"
    }
  }
}

# ============================================================================
# Сервисные аккаунты
# ============================================================================

resource "yandex_iam_service_account" "k8s_sa" {
  name        = "${var.environment}-k8s-sa"
  description = "Service account for Managed Kubernetes cluster"
}

resource "yandex_iam_service_account" "node_sa" {
  name        = "${var.environment}-k8s-node-sa"
  description = "Service account for Kubernetes nodes"
}

# ============================================================================
# Роли сервисных аккаунтов
# ============================================================================

resource "yandex_resourcemanager_folder_iam_member" "k8s_sa_roles" {
  for_each = toset([
    "k8s.clusters.agent",
    "vpc.publicAdmin",
    "load-balancer.admin",
    "logging.writer",
  ])

  folder_id = var.folder_id
  role      = each.value
  member    = "serviceAccount:${yandex_iam_service_account.k8s_sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "node_sa_roles" {
  for_each = toset([
    "container-registry.images.puller",
  ])

  folder_id = var.folder_id
  role      = each.value
  member    = "serviceAccount:${yandex_iam_service_account.node_sa.id}"
}

# ============================================================================
# Задержка для применения IAM-политик
# ============================================================================

resource "time_sleep" "wait_for_iam" {
  create_duration = "5s"

  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s_sa_roles,
    yandex_resourcemanager_folder_iam_member.node_sa_roles,
  ]
}

# ============================================================================
# Управляемый кластер Kubernetes
# ============================================================================

resource "yandex_kubernetes_cluster" "this" {
  name        = "${var.environment}-managed-k8s"
  description = "Managed Kubernetes cluster for ${var.environment}"
  network_id  = var.network_id

  master {
    version = var.k8s_version
    zonal {
      zone      = var.zone
      subnet_id = var.subnet_id
    }

    public_ip = true

    security_group_ids = [var.cluster_security_group_id]

    master_logging {
      enabled = true
    }
  }

  service_account_id      = yandex_iam_service_account.k8s_sa.id
  node_service_account_id = yandex_iam_service_account.node_sa.id

  network_policy_provider = "CALICO"
  release_channel         = "STABLE"

  # 👈 КРИТИЧНО: ждём применения IAM-ролей
  depends_on = [
    time_sleep.wait_for_iam,
  ]
}

# ============================================================================
# Группа узлов
# ============================================================================

resource "yandex_kubernetes_node_group" "workers" {
  cluster_id  = yandex_kubernetes_cluster.this.id
  name        = "${var.environment}-worker-group"
  description = "Worker node group for ${var.environment}"
  version     = var.k8s_version

  labels = {
    environment = var.environment
  }

  scale_policy {
    fixed_scale {
      size = var.worker_count
    }
  }

  allocation_policy {
    location {
      zone = var.zone
    }
  }

  instance_template {
    platform_id = "standard-v3"

    network_interface {
      nat                = true
      subnet_ids         = [var.subnet_id]
      security_group_ids = [var.worker_security_group_id]
    }

    resources {
      cores  = var.worker_cores
      memory = var.worker_memory
    }

    boot_disk {
      type = "network-hdd"
      size = var.worker_disk_size
    }

    container_runtime {
      type = "containerd"
    }

    scheduling_policy {
      preemptible = false
    }
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true

    maintenance_window {
      day        = "monday"
      start_time = "15:00"
      duration   = "3h"
    }
  }
}