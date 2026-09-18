# modules/networking/main.tf

terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.100.0"
    }
  }
}

# ============================================================================
# 1. VPC
# ============================================================================

resource "yandex_vpc_network" "this" {
  name        = "${var.environment}-vpc"
  description = "VPC for ${var.environment} environment"

  labels = merge(
    {
      environment = var.environment
      managed_by  = "terraform"
    },
    var.tags
  )
}

# ============================================================================
# 2. Подсети
# ============================================================================

resource "yandex_vpc_subnet" "this" {
  count = length(var.subnet_cidrs)

  name           = "${var.environment}-subnet-${count.index + 1}"
  description    = "Subnet ${count.index + 1} for ${var.environment} environment"
  zone           = var.zones[count.index % length(var.zones)]
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [var.subnet_cidrs[count.index]]

  # Для доступа в интернет через NAT
  route_table_id = var.enable_nat ? yandex_vpc_route_table.nat[0].id : null

  labels = merge(
    {
      environment = var.environment
      zone        = var.zones[count.index % length(var.zones)]
      managed_by  = "terraform"
    },
    var.tags
  )
}

# ============================================================================
# 3. Маршрутизация
# ============================================================================

resource "yandex_vpc_gateway" "nat" {
  count = var.enable_nat ? 1 : 0

  name        = "${var.environment}-nat-gateway"
  description = "NAT Gateway for ${var.environment} environment"

  shared_egress_gateway {}

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "yandex_vpc_route_table" "nat" {
  count = var.enable_nat ? 1 : 0

  name        = "${var.environment}-nat-route-table"
  description = "Route table for NAT Gateway"
  network_id  = yandex_vpc_network.this.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat[0].id
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# ============================================================================
# 4. Фаерволл
# ============================================================================

# 4.1. Security Group для Control Plane нод
resource "yandex_vpc_security_group" "control_plane" {
  name        = "${var.environment}-sg-control-plane"
  description = "Security group for control-plane nodes"
  network_id  = yandex_vpc_network.this.id

  # === Входящие правила ===

  # SSH
  ingress {
    protocol       = "TCP"
    description    = "SSH access"
    port           = 22
    v4_cidr_blocks = var.ssh_allowed_cidrs
  }

  # Kubernetes API (443 - для управляемого кластера Yandex Cloud)
  ingress {
    protocol       = "TCP"
    description    = "Kubernetes API (HTTPS)"
    port           = 443
    v4_cidr_blocks = var.api_allowed_cidrs
  }

  # Kubernetes API (6443 - для доступа к API напрямую)
  ingress {
    protocol       = "TCP"
    description    = "Kubernetes API"
    port           = 6443
    v4_cidr_blocks = var.api_allowed_cidrs
  }

  # Etcd (внутреннее общение между мастер-нодами)
  ingress {
    protocol       = "TCP"
    description    = "Etcd"
    port           = 2379
    v4_cidr_blocks = [var.vpc_cidr]
  }

  # Kubelet API
  ingress {
    protocol       = "TCP"
    description    = "Kubelet API"
    port           = 10250
    v4_cidr_blocks = [var.vpc_cidr]
  }

  # Внутреннее общение: VPC + pods + services
  ingress {
    protocol       = "ANY"
    description    = "All internal traffic (VPC + pods + services)"
    v4_cidr_blocks = [var.vpc_cidr, var.pod_cidr, var.service_cidr]
    from_port      = 0
    to_port        = 65535
  }

  # Исходящие правила
  egress {
    protocol       = "ANY"
    description    = "All egress traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

  labels = {
    environment = var.environment
    role        = "control-plane"
    managed_by  = "terraform"
  }
}

# 4.2. Security Group для Worker нод
resource "yandex_vpc_security_group" "workers" {
  name        = "${var.environment}-sg-workers"
  description = "Security group for worker nodes"
  network_id  = yandex_vpc_network.this.id

  # === Входящие правила ===

  # SSH
  ingress {
    protocol       = "TCP"
    description    = "SSH access"
    port           = 22
    v4_cidr_blocks = var.ssh_allowed_cidrs
  }

  # Kubelet API
  ingress {
    protocol       = "TCP"
    description    = "Kubelet API"
    port           = 10250
    v4_cidr_blocks = [var.vpc_cidr]
  }

  # Health checks от LoadBalancer (legacy)
  ingress {
    protocol          = "TCP"
    description       = "Health checks from LoadBalancer (10501, legacy)"
    port              = 10501
    predefined_target = "loadbalancer_healthchecks"
  }

  # kube-proxy health check от LoadBalancer
  ingress {
    protocol          = "TCP"
    description       = "kube-proxy health check from LoadBalancer (10256)"
    port              = 10256
    predefined_target = "loadbalancer_healthchecks"
  }

  # HTTP от LoadBalancer
  ingress {
    protocol       = "TCP"
    description    = "HTTP from LoadBalancer"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS от LoadBalancer
  ingress {
    protocol       = "TCP"
    description    = "HTTPS from LoadBalancer"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # NodePort services
  ingress {
    protocol       = "TCP"
    description    = "NodePort services"
    from_port      = 30000
    to_port        = 32767
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Внутреннее общение: VPC + pods + services
  ingress {
    protocol       = "ANY"
    description    = "All internal traffic (VPC + pods + services)"
    v4_cidr_blocks = [var.vpc_cidr, var.pod_cidr, var.service_cidr]
    from_port      = 0
    to_port        = 65535
  }

  # Исходящие правила
  egress {
    protocol       = "ANY"
    description    = "All egress traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

  labels = {
    environment = var.environment
    role        = "worker"
    managed_by  = "terraform"
  }
}

# 4.3. Security Group для GitLab Runner
resource "yandex_vpc_security_group" "gitlab_runner" {
  name        = "${var.environment}-sg-gitlab-runner"
  description = "Security group for GitLab Runner"
  network_id  = yandex_vpc_network.this.id

  ingress {
    protocol       = "TCP"
    description    = "SSH access"
    port           = 22
    v4_cidr_blocks = var.ssh_allowed_cidrs
  }

  ingress {
    protocol       = "TCP"
    description    = "GitLab Runner API"
    port           = 8093
    v4_cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    protocol       = "ANY"
    description    = "All internal traffic (VPC + pods + services)"
    v4_cidr_blocks = [var.vpc_cidr, var.pod_cidr, var.service_cidr]
    from_port      = 0
    to_port        = 65535
  }

  egress {
    protocol       = "ANY"
    description    = "All egress traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

  labels = {
    environment = var.environment
    role        = "gitlab-runner"
    managed_by  = "terraform"
  }
}

# 4.4. Security Group для балансировщика нагрузки
resource "yandex_vpc_security_group" "ingress_lb" {
  name        = "${var.environment}-sg-ingress-lb"
  description = "Security group for Ingress LoadBalancer"
  network_id  = yandex_vpc_network.this.id

  ingress {
    protocol       = "TCP"
    description    = "HTTP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    description    = "HTTPS"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol          = "TCP"
    description       = "Health checks"
    port              = 10501
    predefined_target = "loadbalancer_healthchecks"
  }

  egress {
    protocol       = "ANY"
    description    = "All egress traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

  labels = {
    environment = var.environment
    role        = "ingress-lb"
    managed_by  = "terraform"
  }
}