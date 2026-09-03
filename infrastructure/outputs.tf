# infrastructure/outputs.tf

# ============================================================================
# Выходные данные сети
# ============================================================================

output "vpc_id" {
  description = "ID VPC"
  value       = module.networking.vpc_id
}

output "subnet_ids" {
  description = "Список ID подсетей"
  value       = module.networking.subnet_ids
}

# ============================================================================
# Выходные данные Kubernetes кластера
# ============================================================================

output "control_plane_ip" {
  description = "Внутренний IP control-plane"
  value       = module.kubernetes_cluster.control_plane_ip
}

output "control_plane_nat_ip" {
  description = "Публичный IP control-plane"
  value       = module.kubernetes_cluster.control_plane_nat_ip
}

output "worker_ips" {
  description = "Список внутренних IP worker нод"
  value       = module.kubernetes_cluster.worker_ips
}

output "worker_nat_ips" {
  description = "Список публичных IP worker нод"
  value       = module.kubernetes_cluster.worker_nat_ips
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = module.kubernetes_cluster.cluster_endpoint
}

output "get_kubeconfig_command" {
  description = "Команда для получения kubeconfig"
  value       = module.kubernetes_cluster.get_kubeconfig_command
}

output "ssh_control_plane_command" {
  description = "Команда для SSH на control-plane"
  value       = module.kubernetes_cluster.ssh_control_plane_command
}

# ============================================================================
# Выходные данные GitLab Runner
# ============================================================================

output "gitlab_runner_ip" {
  description = "IP адрес GitLab Runner"
  value       = local.environment != "dev" ? module.gitlab_runner[0].ip : null
}

output "gitlab_runner_ssh" {
  description = "Команда для SSH на GitLab Runner"
  value       = local.environment != "dev" ? module.gitlab_runner[0].ssh : null
}

# ============================================================================
# Информация о кластере
# ============================================================================

output "cluster_info" {
  description = "Общая информация о кластере"
  value = {
    environment       = local.environment
    worker_count      = var.worker_count[local.environment]
    control_plane_ip  = module.kubernetes_cluster.control_plane_ip
    control_plane_nat = module.kubernetes_cluster.control_plane_nat_ip
    cluster_endpoint  = module.kubernetes_cluster.cluster_endpoint
    has_gitlab_runner = local.environment != "dev"
    gitlab_runner_ip  = local.environment != "dev" ? module.gitlab_runner[0].ip : null
  }
}