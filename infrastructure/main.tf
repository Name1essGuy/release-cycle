# infrastructure/main.tf

terraform {
  required_version = ">= 1.5.0"
}

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
  api_allowed_cidrs = ["0.0.0.0/0"] # Для учебного проекта

  tags = var.tags
}

# ============================================================================
# Модуль: Kubernetes Cluster
# ============================================================================

module "kubernetes_cluster" {
  source = "./modules/kubernetes-cluster"

  environment  = local.environment
  worker_count = var.worker_count[local.environment]

  control_plane_instance_type = var.control_plane_instance_type[local.environment]
  worker_instance_type        = var.worker_instance_type[local.environment]

  subnet_ids                      = module.networking.subnet_ids
  zones                           = module.networking.subnet_zones
  control_plane_security_group_id = module.networking.control_plane_security_group_id
  workers_security_group_id       = module.networking.workers_security_group_id

  ssh_public_key = file(var.ssh_public_key_path)

  pod_network_cidr   = var.pod_network_cidr
  kubernetes_version = var.kubernetes_version
  cluster_name       = "${local.environment}-cluster"

  tags = var.tags
}

# ============================================================================
# Чтение join-команды из локального файла (создаётся модулем kubernetes-cluster)
# ============================================================================

data "local_file" "join_command" {
  depends_on = [module.kubernetes_cluster]
  filename   = "./join-command.txt"
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

# Убеждаемся, что сеть создана до кластера
resource "null_resource" "depends_on_networking" {
  depends_on = [module.networking]
}

# Убеждаемся, что кластер создан до раннера
resource "null_resource" "depends_on_cluster" {
  depends_on = [module.kubernetes_cluster]
}