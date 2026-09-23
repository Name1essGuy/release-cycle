# Observability: Prometheus + Grafana

## 📋 Описание

В кластере развёрнут стек наблюдаемости на базе **`kube-prometheus-stack`** — официального Helm-чарта Prometheus Community. Он объединяет:

- **Prometheus** — сбор и хранение метрик.
- **Grafana** — визуализация и алертинг.
- **Alertmanager** — отключён (алерты идут через Grafana Alerting).
- **node-exporter** — метрики нод (DaemonSet на каждой ноде).
- **kube-state-metrics** — метрики объектов Kubernetes.

Prometheus Operator управляет жизненным циклом Prometheus и подхватывает `ServiceMonitor`/`PodMonitor` из чартов приложений.

Устанавливается **автоматически** через скрипт `infrastructure/scripts/setup-monitoring.sh`, который вызывается из `apply.sh` после `setup-ingress-nginx.sh`.

> **Ресурсы мониторинга создаёт чарт `momo-store`** — `ServiceMonitor`, `ConfigMap` с дашбордами и алертами. Стек `kube-prometheus-stack` их только подхватывает. Подробнее — в [Helm: architecture](../helm/architecture.md#monitoring).

---

## 🏗 Архитектура

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Kubernetes cluster                                                       │
│                                                                          │
│  ┌─────────────────────────┐                                             │
│  │ namespace: default      │                                             │
│  │                         │                                             │
│  │  ┌──────────────────┐   │    scrape    ┌────────────────────────────┐ │
│  │  │ momo-store-      │◄──┼──────────────┤                            │ │
│  │  │ backend          │   │  /metrics    │ namespace: monitoring      │ │
│  │  │ (Go app)         │   │              │                            │ │
│  │  │ ServiceMonitor   │   │              │  ┌──────────────────────┐  │ │
│  │  └──────────────────┘   │              │  │ Prometheus           │  │ │
│  │                         │              │  │ (kube-prometheus)    │  │ │
│  │  ┌──────────────────┐   │              │  └──────────┬───────────┘  │ │
│  │  │ momo-store-      │   │              │             │              │ │
│  │  │ frontend         │   │              │             │ query        │ │
│  │  └──────────────────┘   │              │             ▼              │ │
│  └─────────────────────────┘              │  ┌──────────────────────┐  │ │
│                                            │  │ Grafana              │  │ │
│  ┌─────────────────────────┐              │  │ (Alerting + UI)      │  │ │
│  │ kube-system             │              │  └──────────┬───────────┘  │ │
│  │ • kubelet               │───scrape────►│             │              │ │
│  │ • coredns               │              │             │ ingress      │ │
│  │ • kube-proxy            │              │             ▼              │ │
│  │ • kube-apiserver        │              │  ┌──────────────────────┐  │ │
│  └─────────────────────────┘              │  │ ingress-nginx        │  │ │
│                                            │  │ /monitoring → Grafana│  │ │
│  ┌─────────────────────────┐              │  └──────────────────────┘  │ │
│  │ DaemonSet node-exporter │───scrape────►│                            │ │
│  │ (на каждой ноде)        │              └────────────────────────────┘ │
│  └─────────────────────────┘                                             │
└──────────────────────────────────────────────────────────────────────────┘
```

Grafana доступна снаружи по `http://<EXTERNAL-IP>/monitoring`.

---

## 📁 Структура

```
infrastructure/
└── scripts/
    ├── setup-monitoring.sh       # установка стека (вызывается из apply.sh)
    └── verify.sh                 # end-to-end проверка после деплоя

k8s/helm/momo-store/
└── templates/
    └── monitoring/
        ├── servicemonitor.yaml       # Prometheus scrape /metrics бэкенда
        ├── grafana-dashboards.yaml   # ConfigMap с дашбордами (namespace default)
        ├── grafana-alerting.yaml     # ConfigMap с алертами (namespace monitoring)
        └── prometheusrule.yaml       # CRD с алертами для UI Grafana (legacy)
```

> **Namespace'ы ConfigMap'ов различаются:**
>
> | ConfigMap | Namespace | Почему |
> |---|---|---|
> | `momo-store-grafana-dashboards` | `default` | dashboards-sidecar с `searchNamespace=ALL` |
> | `momo-store-grafana-alerting` | `monitoring` | alerts-sidecar смотрит только в свой namespace |
>
> Это значит, что у `ci-deployer` должны быть права на `configmaps` в `monitoring` — иначе деплой из CI упадёт с `Forbidden`. См. [CI/CD: переменные](../ci-cd/variables.md#-kube_config_staging).

---

## 🔧 Установка

Установка происходит **автоматически** при `./scripts/apply.sh staging`:

1. Terraform создаёт кластер и networking.
2. `setup-ingress-nginx.sh` ставит ingress-nginx.
3. **`setup-monitoring.sh`** ставит `kube-prometheus-stack`.
4. `setup-ci-rbac.sh` настраивает RBAC для CI (включая namespace `monitoring`).

### Ручной запуск

```bash
cd infrastructure

export GRAFANA_ADMIN_PASSWORD="StrongAdminPass123"
export GRAFANA_SMTP_EMAIL="youremail@gmail.com"
export GRAFANA_SMTP_PASSWORD="xxxx xxxx xxxx xxxx"   # App Password Gmail

./scripts/setup-monitoring.sh staging
```

### Переменные окружения

| Переменная | Обязательна | Описание |
|---|---|---|
| `GRAFANA_ADMIN_PASSWORD` | ✅ | Пароль пользователя `admin` в Grafana |
| `GRAFANA_SMTP_EMAIL` | ✅ | Gmail-адрес: SMTP user, from_address и получатель алертов |
| `GRAFANA_SMTP_PASSWORD` | ✅ | App Password Gmail (16 символов, без пробелов) |
| `MONITORING_NAMESPACE` | ❌ | Namespace, по умолчанию `monitoring` |
| `KUBE_PROM_STACK_VERSION` | ❌ | Версия Helm-чарта, по умолчанию `65.5.1` |

> **`GRAFANA_SMTP_EMAIL` также нужна в GitLab CI** — передаётся в `deploy:staging` как `--set monitoring.alerting.email`. Без неё `helm upgrade` упадёт при `monitoring.alerting.enabled=true`. См. [CI/CD: переменные](../ci-cd/variables.md#-grafana_smtp_email).

### Как получить Gmail App Password

1. Включить 2FA в Google Account.
2. Перейти: **Security → 2-Step Verification → App passwords**.
3. Создать пароль для Mail → Other (Grafana).
4. Скопировать 16-символьный пароль.
5. `export GRAFANA_SMTP_PASSWORD="xxxx xxxx xxxx xxxx"`.

**Обычный пароль Gmail не подойдёт** — только App Password.

---

## 📊 Что собирается

### Scrape targets

Prometheus скрейпит:

| Target | Что даёт |
|---|---|
| `momo-store-backend` (через ServiceMonitor) | Метрики приложения: `response_timing_ms`, `requests_count`, `orders_count`, `dumplings_listing_count` |
| `kubelet` | Метрики kubelet каждой ноды |
| `kube-state-metrics` | Метрики объектов K8s (поды, деплойменты, сервисы) |
| `node-exporter` | CPU, RAM, диск, сеть каждой ноды |
| `kube-apiserver` | Метрики API-сервера |
| `coredns` | Метрики DNS |
| `kube-proxy` | Метрики kube-proxy (в Managed K8s часто `DOWN` — это нормально) |
| `grafana` | Метрики самой Grafana |
| `prometheus-operator` | Метрики оператора |
| `ingress-nginx` | Метрики ingress-controller (ServiceMonitor с меткой `release=monitoring`) |

### Retention

- **Время хранения:** 7 дней.
- **Размер:** до 10 GiB.
- Хранилище: PVC с дефолтным StorageClass кластера (`emptyDir` если PVC не задан).

---

## 🌐 Доступ к Grafana

### URL

```
http://<EXTERNAL-IP>/monitoring
```

`<EXTERNAL-IP>` — внешний IP сервиса `ingress-nginx-controller`:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

### Аутентификация

- **Login:** `admin`
- **Password:** значение `GRAFANA_ADMIN_PASSWORD` из `setup-monitoring.sh`

### Как устроен subpath

Grafana работает под `/monitoring`, а не под `/`. Это требует:

```ini
[server]
root_url = %(protocol)s://%(domain)s:%(http_port)s/monitoring
serve_from_sub_path = true
```

Эти параметры передаются в `setup-monitoring.sh` через `--set grafana.grafana.ini.server.*`.

---

## 📈 Дашборды

Всего три дашборда, все с тегом `momo-store`:

| Дашборд | Что показывает |
|---|---|
| **Momo Store — Overview** | RED: Traffic (req/s), Latency p50/p95/p99, Backend pods ready, Frontend pods ready |
| **Momo Store — Business** | Orders per minute, Total orders (24h), Top-10 dumplings |
| **Momo Store — Infrastructure** | CPU, RAM, network, restarts по подам |

Дашборды деплоятся через `ConfigMap` `momo-store-grafana-dashboards` с меткой `grafana_dashboard: "1"`. Sidecar Grafana (`grafana-sc-dashboard`) подхватывает их и загружает в Grafana.

**Стандартные дашборды `kube-prometheus-stack` отключены** через `grafana.defaultDashboardsEnabled=false` — чтобы не было мусора.

Подробнее — [dashboards.md](./dashboards.md).

---

## 🚨 Алерты

Алерты работают через **Grafana Alerting** (встроенный механизм).

### Текущие правила

| Правило | Условие | For |
|---|---|---|
| `Node CPU usage > 85%` | `(1 - avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100 > 85` | 5m |
| `Node disk usage > 85%` | `(1 - node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 > 85` | 10m |
| `Node network receive errors` | `rate(node_network_receive_errs_total[5m]) > 10` | 5m |
| `Node network transmit errors` | `rate(node_network_transmit_errs_total[5m]) > 10` | 5m |

Все — в папке **Infrastructure**, группа `node-health`.

### Уведомления

- **Contact point:** `gmail-alerts` → `${GRAFANA_SMTP_EMAIL}`.
- **Notification policy:** default → `gmail-alerts`.
- **Group wait:** 30s, **group interval:** 5m, **repeat interval:** 4h.

Алерты деплоятся через `ConfigMap` `momo-store-grafana-alerting` с меткой `grafana_alert: "1"` **в namespace `monitoring`**.

Подробнее — [alerts.md](./alerts.md).

### `PrometheusRule` — legacy

В чарте также есть `PrometheusRule/momo-store-alerts` (CRD от Prometheus Operator). Он создаётся в namespace `default` и содержит три правила:

- `MomoStoreHighLatencyP95`
- `MomoStoreBackendDown`
- `MomoStoreHighCpu`

Эти правила видны в **Grafana → Alerting → Alert rules** (папка `momo-store`), но **не отправляют email** — Alertmanager отключён. Они используются только для визуального контроля в UI.

Если нужно, чтобы и они отправляли письма — перенесите их в `grafana-alerting.yaml` (в формат Grafana Alerting). Подробнее — в [alerts.md → «Что не отправляется»](./alerts.md#-что-не-отправляется).

---

## ✅ Проверка после деплоя

### 1. `verify.sh`

End-to-end проверка через EXTERNAL-IP:

```bash
cd infrastructure
./scripts/verify.sh
```

Проверяет:

- Поды backend и frontend `Ready`.
- ServiceMonitor и ConfigMap дашбордов созданы.
- Сайт открывается по `EXTERNAL-IP`.
- Статика проксируется как JS.
- `/api/products` возвращает JSON.

### 2. Метрики собираются

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# → http://localhost:9090/targets
```

Ищите `serviceMonitor/default/momo-store-backend/0` — должен быть `UP`.

### 3. Дашборды загружены

```bash
kubectl get configmap -n default momo-store-grafana-dashboards
kubectl logs -n monitoring deploy/monitoring-grafana -c grafana-sc-dashboard --tail=20
```

Ищите строки `Writing /tmp/dashboards/momo-store-*.json`.

### 4. Алерты активны

```bash
kubectl get configmap -n monitoring momo-store-grafana-alerting
```

В Grafana → **Alerting → Alert rules** → папка `Infrastructure` → группа `node-health`. Должны быть четыре правила в статусе `Normal`.

---

## 🔧 Команды

### Проверка состояния

```bash
# Поды мониторинга
kubectl get pods -n monitoring

# Сервисы
kubectl get svc -n monitoring

# Ingress Grafana
kubectl get ingress -n monitoring

# ServiceMonitor
kubectl get servicemonitor -A

# Prometheus targets (в UI)
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# → http://localhost:9090/targets
```

### Доступ к Grafana через port-forward

Если Ingress недоступен:

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# → http://localhost:3000
```

### Логи

```bash
# Grafana
kubectl logs -n monitoring deploy/monitoring-grafana -c grafana

# Sidecar дашбордов
kubectl logs -n monitoring deploy/monitoring-grafana -c grafana-sc-dashboard

# Sidecar алертов
kubectl logs -n monitoring deploy/monitoring-grafana -c grafana-sc-alerts

# Prometheus
kubectl logs -n monitoring prometheus-monitoring-kube-prometheus-prometheus-0 -c prometheus
```

### Перезапуск

```bash
# Grafana
kubectl rollout restart deploy -n monitoring monitoring-grafana

# Prometheus
kubectl delete pod -n monitoring prometheus-monitoring-kube-prometheus-prometheus-0
```

---

## 🔒 Безопасность

### Секреты

- `GRAFANA_ADMIN_PASSWORD` и `GRAFANA_SMTP_PASSWORD` **не коммитятся** в git.
- SMTP-пароль хранится в Kubernetes Secret `grafana-smtp-secret` в namespace `monitoring`.
- Grafana читает пароль через `$__file{/etc/secrets/smtp-password/password}` — так требует Grafana Helm-чарт с v11+.

### Доступ

- Grafana доступна **снаружи** через ingress-nginx по IP.
- **Аутентификация** — только admin-пароль, RBAC внутри Grafana не настроен.
- SMTP идёт через **Gmail** с App Password (не основной пароль аккаунта).

### RBAC для CI

Деплой чарта `momo-store` из CI требует у `ci-deployer` прав на:

- `servicemonitors`, `prometheusrules`, `podmonitors` в namespace `default` — группа `monitoring.coreos.com`;
- `configmaps` в namespace `monitoring` — для ConfigMap алертов.

Проверить:

```bash
KUBECONFIG=/tmp/kubeconfig-ci kubectl auth can-i create servicemonitors -n default
KUBECONFIG=/tmp/kubeconfig-ci kubectl auth can-i create configmaps -n monitoring
```

Оба должны вернуть `yes`. Если нет — см. [CI/CD: переменные](../ci-cd/variables.md#-kube_config_staging).

---

## 🧹 Удаление

```bash
# Удалить Helm-релиз
helm uninstall monitoring -n monitoring

# Удалить namespace (вместе с PVC, ConfigMap, Secret)
kubectl delete namespace monitoring
```

**Что останется после удаления:**

- CRD `*.monitoring.coreos.com` — cluster-wide, не удаляются вместе с релизом. Если не планируете переустанавливать — удалите вручную:
  ```bash
  kubectl get crd | grep monitoring.coreos.com
  kubectl delete crd <name>
  ```
- `PrometheusRule/momo-store-alerts` в namespace `default` — создаётся чартом `momo-store`, а не `kube-prometheus-stack`. Удалится при `helm uninstall momo-store`, если Helm успел удалить CRD. Если CRD уже нет — удалите вручную:
  ```bash
  kubectl delete prometheusrule momo-store-alerts -n default --ignore-not-found
  ```

---

## 📚 Ссылки

- [Дашборды](./dashboards.md) — что показывает каждый дашборд
- [Алерты](./alerts.md) — какие алерты, как настроены, как проверить
- [Helm: architecture](../helm/architecture.md) — как чарт `momo-store` создаёт ресурсы мониторинга
- [Helm: deployment](../helm/deployment.md) — деплой, troubleshooting
- [CI/CD: переменные](../ci-cd/variables.md) — `GRAFANA_SMTP_EMAIL`, RBAC на `monitoring`
- [CI/CD: диагностика](../ci-cd/diagnostics.md) — `diag:monitoring`
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) — официальный чарт
- [Grafana Alerting Provisioning](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/) — документация по provisioning