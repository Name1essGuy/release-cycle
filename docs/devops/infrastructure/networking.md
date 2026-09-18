# Модуль Networking

## 📋 Описание

Модуль создаёт сетевую инфраструктуру для Kubernetes-кластера в Yandex Cloud:

- изолированную VPC;
- подсети в нескольких зонах доступности;
- NAT Gateway для выхода в интернет;
- security groups для всех компонентов кластера: control-plane, workers, GitLab Runner и Ingress LoadBalancer.

Модуль не создаёт сам кластер и не управляет им - только сеть.

---

## 🎯 Что создаётся

| Ресурс | Terraform resource | Назначение |
|---|---|---|
| VPC | `yandex_vpc_network.this` | Изолированная сеть |
| Подсети | `yandex_vpc_subnet.this[*]` | По одной на каждый CIDR |
| NAT Gateway | `yandex_vpc_gateway.nat[0]` | Выход в интернет (опционально) |
| Route Table | `yandex_vpc_route_table.nat[0]` | Маршрутизация через NAT |
| SG control-plane | `yandex_vpc_security_group.control_plane` | Для master-нод |
| SG workers | `yandex_vpc_security_group.workers` | Для worker-нод |
| SG GitLab Runner | `yandex_vpc_security_group.gitlab_runner` | Для CI-runner |
| SG Ingress LB | `yandex_vpc_security_group.ingress_lb` | Для балансировщика ingress-nginx |

---

## 📁 Структура модуля

```
modules/networking/
├── main.tf        # Ресурсы VPC, подсетей, NAT и security groups
├── variables.tf   # Входные переменные
└── outputs.tf     # Выходные значения
```

---

## 📥 Входные переменные

| Переменная | Тип | По умолчанию | Описание |
|---|---|---|---|
| `environment` | string | - | Окружение: `dev`, `staging`, `prod` |
| `vpc_cidr` | string | `10.0.0.0/16` | CIDR блок VPC |
| `subnet_cidrs` | list(string) | `["10.0.1.0/24", "10.0.2.0/24"]` | CIDR блоки подсетей |
| `zones` | list(string) | `["ru-central1-a", "ru-central1-b"]` | Зоны доступности для подсетей |
| `enable_nat` | bool | `true` | Включать ли NAT Gateway |
| `ssh_allowed_cidrs` | list(string) | `["0.0.0.0/0"]` | CIDR, с которых разрешён SSH |
| `api_allowed_cidrs` | list(string) | `["0.0.0.0/0"]` | CIDR, с которых разрешён Kubernetes API |
| `pod_cidr` | string | `10.112.0.0/16` | CIDR подов (должен совпадать с кластером) |
| `service_cidr` | string | `10.96.0.0/16` | CIDR сервисов (должен совпадать с кластером) |
| `tags` | map(string) | `{}` | Дополнительные метки для ресурсов |

### Важные замечания по переменным

- **`pod_cidr` и `service_cidr` должны совпадать с реальными диапазонами кластера.** Они задаются в `modules/kubernetes-cluster` через `cluster_ipv4_range` и `service_ipv4_range`. Если тут значения другие, SG не пропустит pod-to-pod и pod-to-service трафик, что проявится как «DNS не работает», «CoreDNS недоступен», «502 при обращении к S3 из nginx».
- **`ssh_allowed_cidrs` и `api_allowed_cidrs` в учебном проекте - `0.0.0.0/0`.** Для production ограничьте конкретными IP.
- **`enable_nat = false`** ломает egress в интернет: worker-ноды не смогут скачивать образы, а nginx - ходить в S3. Используйте только для полностью изолированных окружений.

---

## 📤 Выходные значения

| Output | Описание |
|---|---|
| `vpc_id` | ID VPC |
| `vpc_name` | Имя VPC |
| `subnet_ids` | Список ID подсетей |
| `subnet_cidrs` | Список CIDR подсетей |
| `subnet_zones` | Список зон доступности подсетей |
| `control_plane_security_group_id` | ID SG для control-plane нод |
| `workers_security_group_id` | ID SG для worker нод |
| `gitlab_runner_security_group_id` | ID SG для GitLab Runner |
| `ingress_lb_security_group_id` | ID SG для Ingress LoadBalancer |
| `nat_gateway_id` | ID NAT Gateway (или `null`) |
| `route_table_id` | ID route table (или `null`) |

---

## 🚀 Использование

```hcl
module "networking" {
  source = "./modules/networking"

  environment  = local.environment
  vpc_cidr     = var.vpc_cidr[local.environment]
  subnet_cidrs = var.subnet_cidrs[local.environment]
  zones        = var.zones[local.environment]
  enable_nat   = true

  ssh_allowed_cidrs = var.ssh_allowed_cidrs[local.environment]
  api_allowed_cidrs = ["0.0.0.0/0"]

  pod_cidr     = "10.112.0.0/16"
  service_cidr = "10.96.0.0/16"

  tags = var.tags
}
```

---

## 🔥 Security groups

### `control_plane` (`<env>-sg-control-plane`)

| Направление | Протокол | Порт | Источник | Описание |
|---|---|---|---|---|
| ingress | TCP | 22 | `ssh_allowed_cidrs` | SSH |
| ingress | TCP | 443 | `api_allowed_cidrs` | Kubernetes API (HTTPS) |
| ingress | TCP | 6443 | `api_allowed_cidrs` | Kubernetes API (напрямую) |
| ingress | TCP | 2379 | `vpc_cidr` | Etcd |
| ingress | TCP | 10250 | `vpc_cidr` | Kubelet API |
| ingress | ANY | 0–65535 | `vpc_cidr`, `pod_cidr`, `service_cidr` | Внутренний трафик |
| egress | ANY | 0–65535 | `0.0.0.0/0` | Весь исходящий |

### `workers` (`<env>-sg-workers`)

| Направление | Протокол | Порт | Источник | Описание |
|---|---|---|---|---|
| ingress | TCP | 22 | `ssh_allowed_cidrs` | SSH |
| ingress | TCP | 10250 | `vpc_cidr` | Kubelet API |
| ingress | TCP | 10501 | `loadbalancer_healthchecks` | Health check (legacy) |
| ingress | TCP | 10256 | `loadbalancer_healthchecks` | Health check kube-proxy |
| ingress | TCP | 80 | `0.0.0.0/0` | HTTP от LB |
| ingress | TCP | 443 | `0.0.0.0/0` | HTTPS от LB |
| ingress | TCP | 30000–32767 | `0.0.0.0/0` | NodePort |
| ingress | ANY | 0–65535 | `vpc_cidr`, `pod_cidr`, `service_cidr` | Внутренний трафик |
| egress | ANY | 0–65535 | `0.0.0.0/0` | Весь исходящий |

### `gitlab_runner` (`<env>-sg-gitlab-runner`)

| Направление | Протокол | Порт | Источник | Описание |
|---|---|---|---|---|
| ingress | TCP | 22 | `ssh_allowed_cidrs` | SSH |
| ingress | TCP | 8093 | `vpc_cidr` | GitLab Runner API |
| ingress | ANY | 0–65535 | `vpc_cidr`, `pod_cidr`, `service_cidr` | Внутренний трафик |
| egress | ANY | 0–65535 | `0.0.0.0/0` | Весь исходящий |

### `ingress_lb` (`<env>-sg-ingress-lb`)

| Направление | Протокол | Порт | Источник | Описание |
|---|---|---|---|---|
| ingress | TCP | 80 | `0.0.0.0/0` | HTTP |
| ingress | TCP | 443 | `0.0.0.0/0` | HTTPS |
| ingress | TCP | 10501 | `loadbalancer_healthchecks` | Health checks |
| egress | ANY | 0–65535 | `0.0.0.0/0` | Весь исходящий |

---

## 🔍 Особенности

### Зачем в ingress_lb egress?

NLB (Network Load Balancer) сам не генерирует трафик, но Yandex Cloud требует, чтобы SG для LB имел egress-правило. Без него LB не сможет устанавливать соединения с target group.

### Почему в workers два health check-порта - 10501 и 10256?

- **10501** - исторический порт health check для managed Kubernetes LB. Иногда используется как fallback.
- **10256** - порт `kube-proxy` health endpoint (`/healthz`). Именно на него Yandex Cloud CCM настраивает health check для NLB по умолчанию.

Если в target group health check идёт на 10256, а в SG workers его нет - все ноды будут `UNHEALTHY`, и LB отдаст 503.

### Почему `pod_cidr` и `service_cidr` в SG?

Pod-to-pod и pod-to-service трафик идёт **не через VPC CIDR**, а через pod CIDR и service CIDR. Если их не разрешить, ломается:

- DNS (CoreDNS живёт в подах, ClusterIP в service CIDR);
- доступ подов к API-серверу через `kubernetes.default`;
- любой overlay-трафик через Calico между нодами.

Классический симптом: **nginx не может зарезолвить внешнее имя через `resolver <ClusterIP kube-dns>`** → `could not be resolved (110: Operation timed out)`.

### NAT Gateway

Если `enable_nat = true`, все подсети получают route table с маршрутом `0.0.0.0/0 → NAT Gateway`. Это даёт egress в интернет для подов и нод.

Без NAT:

- поды не могут скачать образы с `cr.yandex`;
- nginx не может проксировать в S3 (`storage.yandexcloud.net`);
- CoreDNS не может форвардить внешние имена.

---

## ✅ Проверка после apply

```bash
# VPC и подсети
yc vpc network list
yc vpc subnet list

# Security groups
yc vpc security-group list

# Проверить конкретную SG
yc vpc security-group get --name staging-sg-workers --format json | jq '.rules[]'

# NAT и route table (если включён)
yc vpc gateway list
yc vpc route-table list
```

---

## 🔗 Связь с другими модулями

Модуль отдаёт ID ресурсов, которые используются:

- `modules/kubernetes-cluster` - `vpc_id`, `subnet_ids`, `control_plane_security_group_id`, `workers_security_group_id`;
- `modules/gitlab-runner` - `subnet_ids[0]`, `gitlab_runner_security_group_id`;
- **Helm-чарт `momo-store`** - `ingress_lb_security_group_id` (через `values-*.yaml` → аннотация `yandex.cloud/security-group-ids` на сервисе ingress-nginx).

---

## ⚠️ Частые проблемы

### `nginx: could not be resolved (110: Operation timed out)`

SG не пропускает pod-to-pod. Проверьте, что в `workers` и `control_plane` SG есть правило с `pod_cidr` и `service_cidr`.

### Target group `UNHEALTHY`

SG `workers` не пропускает health check. Проверьте наличие правила на порт **10256** с `predefined_target = "loadbalancer_healthchecks"`.

### LoadBalancer в таймауте

К LB не привязана SG. Это делается **не в этом модуле**, а в Helm-чарте через аннотацию на сервисе:

```yaml
ingress-nginx:
  controller:
    service:
      annotations:
        yandex.cloud/security-group-ids: "<ingress_lb_security_group_id>"
```

Значение `<ingress_lb_security_group_id>` берётся из output этого модуля:

```bash
terraform output ingress_lb_security_group_id
```

### Подсети без интернета

`enable_nat = false` или NAT Gateway удалён. Проверьте `route_table_id` у подсетей:

```bash
yc vpc subnet get <subnet-id> --format json | jq '.route_table_id'
```

Не должно быть `null`, если нужен egress.

---

## 🧹 Удаление

`terraform destroy -target=module.networking` удалит VPC со всеми подсетями, SG и NAT. **Нельзя** выполнить, пока в VPC есть ресурсы (кластер, ВМ) - сначала удалите их.
