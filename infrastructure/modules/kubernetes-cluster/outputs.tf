# modules/kubernetes-cluster/outputs.tf

output "control_plane_id" {
  description = "ID виртуальной машины control-plane"
  value       = yandex_compute_instance.control_plane.id
}

output "control_plane_name" {
  description = "Имя control-plane"
  value       = yandex_compute_instance.control_plane.name
}

output "control_plane_ip" {
  description = "Внутренний IP адрес control-plane"
  value       = yandex_compute_instance.control_plane.network_interface.0.ip_address
}

output "control_plane_nat_ip" {
  description = "Публичный IP адрес control-plane"
  value       = yandex_compute_instance.control_plane.network_interface.0.nat_ip_address
}

output "worker_ids" {
  description = "Список ID worker нод"
  value       = yandex_compute_instance.workers[*].id
}

output "worker_names" {
  description = "Список имен worker нод"
  value       = yandex_compute_instance.workers[*].name
}

output "worker_ips" {
  description = "Список внутренних IP адресов worker нод"
  value       = yandex_compute_instance.workers[*].network_interface.0.ip_address
}

output "worker_nat_ips" {
  description = "Список публичных IP адресов worker нод"
  value       = yandex_compute_instance.workers[*].network_interface.0.nat_ip_address
}

output "cluster_endpoint" {
  description = "Endpoint Kubernetes API"
  value       = "https://${yandex_compute_instance.control_plane.network_interface.0.ip_address}:6443"
}

output "cluster_nat_endpoint" {
  description = "Публичный endpoint Kubernetes API"
  value       = "https://${yandex_compute_instance.control_plane.network_interface.0.nat_ip_address}:6443"
}

output "get_kubeconfig_command" {
  description = "Команда для получения kubeconfig с control-plane"
  value       = "scp ubuntu@${yandex_compute_instance.control_plane.network_interface.0.nat_ip_address}:/home/ubuntu/.kube/config ./kubeconfig-${var.environment}"
}

output "ssh_control_plane_command" {
  description = "Команда для SSH доступа к control-plane"
  value       = "ssh ubuntu@${yandex_compute_instance.control_plane.network_interface.0.nat_ip_address}"
}
