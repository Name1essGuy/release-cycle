# Модуль Kubernetes Cluster

## 📋 Описание

Модуль создаёт **управляемый** кластер Kubernetes в Yandex Cloud (Managed Service for Kubernetes) с группой worker-нод.

Yandex Cloud берёт на себя control-plane (master-ноды, etcd, kube-apiserver, scheduler, controller-manager), а модуль управляет только параметрами кластера и группой воркеров.

---

## 🎯 Что создаётся

| Ресурс | Terraform resource | Назначение |
|---|---|---|
| Сервисный аккаунт кластера | `yandex_iam_service_account.k8s_sa` | Управление кластером от имени YC |
| Сервисный аккаунт нод | `yandex_iam_service_account.node_sa` | Pull образов из Container Registry |
| Роли SA кластера | `yandex_resourcemanager_folder_iam_member.k8s_sa_roles` | `k8s.clusters.agent`, `vpc.publicAdmin`, `load-balancer.admin`, `logging.writer` |
| Роли SA нод | `yandex_resourcemanager_folder_iam_member.node_sa_roles` | `container-registry.images.puller` |
| Задержка IAM | `time_sleep.wait_for_iam` | 5 секунд, чтобы роли успели примениться |
| Managed K8s кластер | `yandex_kubernetes_cluster.this` | Сам кластер |
| Worker node group | `yandex_kubernetes_node_group.workers` | Группа воркеров |

---

## 📥 Входные переменные

| Переменная | Тип | По умолчанию | Обязательная | Описание |
|---|---|---|---|---|
| `environment` | string | — | ✅ | Окружение: `dev`, `staging`, `prod` |
| `folder_id` | string | — | ✅ | ID каталога |
| `network_id` | string | — | ✅ | ID VPC |
| `subnet_id` | string | — | ✅ | ID подсети |
| `zone` | string | `ru-central1-a` | ❌ | Зона доступности |
| `k8s_version` | string | `1.32` | ❌ | Версия Kubernetes |
| `worker_count` | number | `1` | ❌ | Количество worker-нод |
| `worker_cores` | number | `2` | ❌ | CPU на ноду |
| `worker_memory` | number | `4` | ❌ | RAM на ноду (ГБ) |
| `worker_disk_size` | number | `30` | ❌ | Размер диска (ГБ) |
| `cluster_security_group_id` | string | — | ✅ | SG для control-plane |
| `worker_security_group_id` | string | — | ✅ | SG для worker-нод |
| `tags` | map(string) | `{}` | ❌ | Дополнительные метки |

### Важные замечания по переменным

- **`folder_id` обязателен.** IAM-ресурсы (`yandex_resourcemanager_folder_iam_member`) не подхватывают его из `YC_FOLDER_ID` автоматически.
- **`k8s_version`** — используйте только актуальные версии (1.32–1.35). Старые могут быть недоступны в Yandex Cloud.
- **`worker_count`** — в `dev` обычно 1, в `staging` 2, в `prod` 3.
- **`cluster_security_group_id`** и **`worker_security_group_id`** приходят из `module.networking`.

---

## 📤 Выходные значения

| Output | Sensitive | Описание |
|---|---|---|
| `cluster_id` | нет | ID управляемого кластера |
| `cluster_name` | нет | Имя кластера |
| `cluster_endpoint` | нет | Публичный endpoint Kubernetes API |
| `cluster_ca_certificate` | **да** | CA-сертификат кластера |
| `node_group_id` | нет | ID группы узлов |
| `node_group_name` | нет | Имя группы узлов |

Получить конкретный output:

```bash
terraform output -raw cluster_id
terraform output -raw cluster_endpoint
```

---

## 🚀 Использование

```hcl
module "kubernetes_cluster" {
  source = "./modules/kubernetes-cluster"

  environment = local.environment
  folder_id   = var.folder_id
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
```

---

## 📋 Сервисные аккаунты и роли

### `k8s_sa` — `<env>-k8s-sa`

| Роль | Назначение |
|---|---|
| `k8s.clusters.agent` | Управление кластером от имени YC |
| `vpc.publicAdmin` | Выделение публичных IP для LoadBalancer |
| `load-balancer.admin` | Создание/удаление NLB |
| `logging.writer` | Отправка логов в Yandex Cloud Logging |

### `node_sa` — `<env>-k8s-node-sa`

| Роль | Назначение |
|---|---|
| `container-registry.images.puller` | Pull образов из Container Registry |

> Роли выдаются через `for_each = toset([...])`, что позволяет легко добавлять новые роли в список.

---

## 🔧 Параметры managed-кластера

| Параметр | Значение | Комментарий |
|---|---|---|
| `master.public_ip` | `true` | Публичный endpoint для `kubectl` |
| `master.master_logging.enabled` | `true` | Логи master в YC Logging |
| `network_policy_provider` | `CALICO` | Сетевые политики |
| `release_channel` | `STABLE` | Автообновления в stable-канале |
| `master.zonal.zone` | `var.zone` | Одна зона (не regional) |

---

## 🔧 Параметры worker node group

| Параметр | Значение | Комментарий |
|---|---|---|
| `scale_policy.fixed_scale.size` | `var.worker_count` | Фиксированное число нод |
| `allocation_policy.location.zone` | `var.zone` | Одна зона |
| `instance_template.platform_id` | `standard-v3` | Платформа ВМ |
| `network_interface.nat` | `true` | Публичный IP на каждой ноде |
| `network_interface.security_group_ids` | `[var.worker_security_group_id]` | SG workers |
| `resources.cores` | `var.worker_cores` | 2 CPU |
| `resources.memory` | `var.worker_memory` | 4 ГБ |
| `boot_disk.type` | `network-hdd` | HDD-диск |
| `boot_disk.size` | `var.worker_disk_size` | 30 ГБ |
| `container_runtime.type` | `containerd` | Runtime |
| `scheduling_policy.preemptible` | `false` | Non-preemptible |
| `maintenance_policy.auto_upgrade` | `true` | Авто-обновление |
| `maintenance_policy.auto_repair` | `true` | Авто-восстановление |
| `maintenance_window` | пн 15:00, 3ч | Окно для maintenance |

---

## 🔍 Особенности

### `time_sleep.wait_for_iam`

После выдачи IAM-ролей Terraform может создавать кластер **до того**, как роли реально применятся в облаке. Тогда `k8s.clusters.agent` не сработает, и кластер зависнет в `PROVISIONING`. Ресурс `time_sleep.wait_for_iam` даёт 5 секунд буфер.

### `public_ip = true` на master

Даёт публичный endpoint API-сервера. Удобно для локального `kubectl` и CI, но **небезопасно** для production — открытый API видят все. В prod стоит:

- закрыть доступ через `api_allowed_cidrs` в SG control-plane (уже есть);
- либо использовать `public_ip = false` и ходить через VPN/bastion.

### Network policy provider CALICO

Включён сразу. Позволяет ограничивать трафик между подами, если понадобится.

### Auto upgrade / auto repair

Кластер сам обновляет ноды и восстанавливает их при сбое. `maintenance_window` задаёт время, когда это делается — важно, чтобы попадало в окно низкой нагрузки.

---

## 📚 Связь с другими модулями

| Что использует | Откуда |
|---|---|
| `network_id` | `module.networking.vpc_id` |
| `subnet_id` | `module.networking.subnet_ids[0]` |
| `cluster_security_group_id` | `module.networking.control_plane_security_group_id` |
| `worker_security_group_id` | `module.networking.workers_security_group_id` |

Что **отдаёт**:

- `cluster_id`, `cluster_name`, `cluster_endpoint`, `cluster_ca_certificate` — в `infrastructure/outputs.tf` и дальше в CI;
- `node_group_id`, `node_group_name` — для отладки и мониторинга.

---

## ⚠️ Частые проблемы

### Кластер зависает в `PROVISIONING`

Обычно — не применились IAM-роли. Проверьте:

```bash
yc managed-kubernetes cluster get <cluster-id> --format json | jq '.status'
yc resource-manager folder list-access-bindings <folder-id>
```

Если роли на месте, но кластер всё равно не поднимается — смотрите события:

```bash
yc managed-kubernetes cluster list-operations <cluster-id>
```

### Worker-ноды `NotReady`

Обычно — SG workers не пропускает нужный трафик. Проверьте, что в SG есть:

- kubelet API (10250) из `vpc_cidr`;
- pod CIDR и service CIDR (для overlay-трафика);
- egress `0.0.0.0/0` (для pull образов и связи с API).

### `kubectl` не подключается

```bash
yc managed-kubernetes cluster get-credentials --name <cluster-name> --external --force
kubectl get nodes
```

Если `get-credentials` возвращает ошибку — проверьте права пользователя/SA в каталоге.

### Создание кластера занимает 10–20 минут

Это нормально. Master-ноды разворачиваются долго. Не считайте это зависанием, если статус `PROVISIONING`.

---

## 🧹 Удаление

```bash
terraform destroy -target=module.kubernetes_cluster
```

Удалит кластер и node group. **Нельзя** удалить, пока внутри кластера есть PVC с динамическими дисками, LB-сервисы или ingress-nginx — сначала удалите Helm-релизы.