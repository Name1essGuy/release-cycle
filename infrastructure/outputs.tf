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

output "ingress_lb_security_group_id" {
  description = "ID security group для Ingress LoadBalancer"
  value       = module.networking.ingress_lb_security_group_id
}

output "workers_security_group_id" {
  description = "ID security group для worker нод"
  value       = module.networking.workers_security_group_id
}

output "control_plane_security_group_id" {
  description = "ID security group для control-plane нод"
  value       = module.networking.control_plane_security_group_id
}

# ============================================================================
# Выходные данные Kubernetes кластера
# ============================================================================

output "cluster_id" {
  description = "ID управляемого кластера Kubernetes"
  value       = module.kubernetes_cluster.cluster_id
}

output "cluster_name" {
  description = "Имя кластера"
  value       = module.kubernetes_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = module.kubernetes_cluster.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "CA-сертификат кластера"
  value       = module.kubernetes_cluster.cluster_ca_certificate
  sensitive   = true
}

output "node_group_id" {
  description = "ID группы узлов"
  value       = module.kubernetes_cluster.node_group_id
}

output "node_group_name" {
  description = "Имя группы узлов"
  value       = module.kubernetes_cluster.node_group_name
}

# ============================================================================
# Команда для получения kubeconfig
# ============================================================================

output "get_kubeconfig_command" {
  description = "Команда для получения kubeconfig управляемого кластера"
  value       = "yc managed-kubernetes cluster get-credentials --name ${module.kubernetes_cluster.cluster_name} --external --force"
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