# modules/networking/outputs.tf

output "vpc_id" {
  description = "ID созданной VPC"
  value       = yandex_vpc_network.this.id
}

output "vpc_name" {
  description = "Имя созданной VPC"
  value       = yandex_vpc_network.this.name
}

output "subnet_ids" {
  description = "Список ID созданных подсетей"
  value       = yandex_vpc_subnet.this[*].id
}

output "subnet_cidrs" {
  description = "Список CIDR блоков подсетей"
  value       = yandex_vpc_subnet.this[*].v4_cidr_blocks
}

output "subnet_zones" {
  description = "Список зон доступности подсетей"
  value       = yandex_vpc_subnet.this[*].zone
}

output "control_plane_security_group_id" {
  description = "ID security group для control-plane нод"
  value       = yandex_vpc_security_group.control_plane.id
}

output "workers_security_group_id" {
  description = "ID security group для worker нод"
  value       = yandex_vpc_security_group.workers.id
}

output "gitlab_runner_security_group_id" {
  description = "ID security group для GitLab Runner"
  value       = yandex_vpc_security_group.gitlab_runner.id
}

output "load_balancer_security_group_id" {
  description = "ID security group для балансировщика нагрузки"
  value       = var.environment == "prod" ? yandex_vpc_security_group.load_balancer[0].id : null
}

output "nat_gateway_id" {
  description = "ID NAT Gateway"
  value       = var.enable_nat ? yandex_vpc_gateway.nat[0].id : null
}

output "route_table_id" {
  description = "ID таблицы маршрутизации для NAT"
  value       = var.enable_nat ? yandex_vpc_route_table.nat[0].id : null
}