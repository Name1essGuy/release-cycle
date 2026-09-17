# infrastructure/main.tf


# ============================================================================
# Определение текущего окружения через workspace
# ============================================================================

locals {
  environment = terraform.workspace
}

# ============================================================================
# Модуль: Networking (сеть)
# ============================================================================

module "networking" {
  source = "./modules/networking"

  environment  = local.environment
  vpc_cidr     = var.vpc_cidr[local.environment]
  subnet_cidrs = var.subnet_cidrs[local.environment]
  zones        = var.zones[local.environment]
  enable_nat   = true

  ssh_allowed_cidrs = var.ssh_allowed_cidrs[local.environment]
  api_allowed_cidrs = ["0.0.0.0/0"]

  # Диапазоны кластера, чтобы SG workers/control-plane пропускали
  # pod-to-pod и pod-to-service трафик автоматически.
  pod_cidr     = var.pod_cidr
  service_cidr = var.service_cidr

  tags = var.tags
}

# ============================================================================
# Модуль: Kubernetes Cluster (управляемый)
# ============================================================================

module "kubernetes_cluster" {
  source = "./modules/kubernetes-cluster"

  folder_id   = var.folder_id
  environment = local.environment
  network_id  = module.networking.vpc_id
  subnet_id   = module.networking.subnet_ids[0]
  zone        = var.zones[local.environment][0]

  k8s_version      = var.kubernetes_version
  worker_count     = var.worker_count[local.environment]
  worker_cores     = 2
  worker_memory    = 4
  worker_disk_size = 30

  cluster_security_group_id = module.networking.control_plane_security_group_id
  worker_security_group_id  = module.networking.workers_security_group_id

  tags = var.tags
}

# ============================================================================
# Модуль: GitLab Runner (только для staging и prod)
# ============================================================================

module "gitlab_runner" {
  source = "./modules/gitlab-runner"
  count  = local.environment != "dev" ? 1 : 0

  environment        = local.environment
  gitlab_url         = var.gitlab_url
  gitlab_token       = var.gitlab_token[local.environment]
  subnet_id          = module.networking.subnet_ids[0]
  security_group_ids = [module.networking.gitlab_runner_security_group_id]
  ssh_public_key     = file(var.ssh_public_key_path)
  disk_size          = 20
  tags               = var.tags
}

# ============================================================================
# Зависимости для правильного порядка создания
# ============================================================================

resource "null_resource" "depends_on_networking" {
  depends_on = [module.networking]
}

resource "null_resource" "depends_on_cluster" {
  depends_on = [module.kubernetes_cluster]
}