# Дашборды Grafana

## 📋 Описание

В Grafana загружены **три дашборда** для наблюдения за Momo Store. Все они:

- Имеют тег `momo-store` — легко фильтруются в Grafana.
- Деплоятся через Helm-чарт `momo-store`, а не создаются вручную в UI.
- Загружаются автоматически при `helm upgrade` через sidecar Grafana.

| Дашборд | UID | Что показывает |
|---|---|---|
| **Momo Store — Overview** | `momo-store-overview` | RED-метрики приложения |
| **Momo Store — Business** | `momo-store-business` | Бизнес-метрики: заказы, популярные товары |
| **Momo Store — Infrastructure** | `momo-store-infrastructure` | CPU, RAM, сеть, рестарты подов |

**Стандартные дашборды `kube-prometheus-stack` отключены** (`grafana.defaultDashboardsEnabled=false`) — чтобы не было мусора из 30+ дашбордов Kubernetes.

---

## 🏗 Как дашборды попадают в Grafana

```
┌───────────────────────────────┐
│ k8s/helm/momo-store/          │
│   templates/monitoring/       │
│     grafana-dashboards.yaml   │  ← ConfigMap с JSON-файлами
└──────────────┬────────────────┘
               │ helm upgrade
               ▼
┌───────────────────────────────┐
│ ConfigMap                     │
│   momo-store-grafana-         │
│   dashboards                  │
│   labels:                     │
│     grafana_dashboard: "1"    │
└──────────────┬────────────────┘
               │ sidecar сканирует по метке
               ▼
┌───────────────────────────────┐
│ Sidecar grafana-sc-dashboard  │
│ (в поде Grafana)              │
│                               │
│ Записывает файлы в            │
│ /tmp/dashboards/              │
└──────────────┬────────────────┘
               │ Grafana читает директорию
               ▼
┌───────────────────────────────┐
│ Grafana UI                    │
│ Dashboards → Browse           │
│ тег: momo-store               │
└───────────────────────────────┘
```

**Ключевые компоненты:**

- **ConfigMap** — содержит JSON'ы дашбордов в поле `data`, у каждого файла — свой ключ.
- **Метка `grafana_dashboard: "1"`** — по ней sidecar находит ConfigMap.
- **Sidecar `grafana-sc-dashboard`** — контейнер рядом с Grafana. Сканирует кластер на ConfigMap с меткой, сохраняет файлы на диск Grafana.
- **Параметр `searchNamespace=ALL`** — sidecar ищет во **всех** namespace. Иначе нашёл бы только те, что лежат в `monitoring`, а ConfigMap чарта создаётся в `default`.

**Важно:** ConfigMap создаётся в namespace `default` (там, где развёрнут чарт `momo-store`), а sidecar запущен в `monitoring`. Поэтому `searchNamespace=ALL` **обязателен**.

---

## 📊 Momo Store — Overview

**UID:** `momo-store-overview`
**Теги:** `momo-store`, `red`

Дашборд для быстрого взгляда на состояние приложения. Пять панелей.

### Панели

#### 1. Traffic — Requests per second by handler

**PromQL:**
```promql
sum(rate(response_timing_ms_count{namespace="default"}[5m])) by (handler)
```

**Что показывает:** частоту запросов в секунду, разбитую по HTTP-handler'ам (`/auth/whoami/`, `/categories/`, `/products/` и т.д.). Источник — гистограмма `response_timing_ms` из Go-бэкенда.

**Единица:** `reqps` (requests per second).

**Как читать:** рост трафика — нормально, резкий спад — возможная проблема с фронтом или сетью.

#### 2. Latency — p50 / p95 / p99

**PromQL:**
```promql
histogram_quantile(0.50, sum(rate(response_timing_ms_bucket{namespace="default"}[5m])) by (le))
histogram_quantile(0.95, sum(rate(response_timing_ms_bucket{namespace="default"}[5m])) by (le))
histogram_quantile(0.99, sum(rate(response_timing_ms_bucket{namespace="default"}[5m])) by (le))
```

**Что показывает:** три перцентиля времени ответа бэкенда: медиану, 95-й и 99-й.

**Единица:** `ms` (метрика `response_timing_ms` — в миллисекундах, не в секундах).

**Как читать:**
- p50 < 100ms — норма.
- p95 < 500ms — норма.
- p99 > 1000ms — стоит разбираться.

#### 3. Total request rate

**PromQL:**
```promql
sum(rate(response_timing_ms_count{namespace="default"}[5m]))
```

**Что показывает:** общую частоту запросов ко всем handler'ам вместе.

**Тип:** Single Stat.

#### 4. Backend pods ready

**PromQL:**
```promql
count(kube_pod_status_ready{namespace="default",pod=~"momo-store-backend-.*",condition="true"} == 1)
```

**Что показывает:** сколько подов бэкенда в состоянии `Ready`. Источник — `kube-state-metrics`.

**Ожидаемое значение:** равно `replicaCount` из `values-staging.yaml` (в staging — 1, в prod — 3).

**Если меньше ожидаемого** — проблема с бэкендом, смотрите `kubectl get pods`.

#### 5. Frontend pods ready

**PromQL:**
```promql
count(kube_pod_status_ready{namespace="default",pod=~"momo-store-frontend-.*",condition="true"} == 1)
```

**Что показывает:** сколько подов фронтенда в состоянии `Ready`.

**Внимание:** фронтенд в вашем проекте — это **nginx-прокси к S3**, а не сам сайт. Он всегда должен быть `Ready`, если под работает.

---

## 💰 Momo Store — Business

**UID:** `momo-store-business`
**Теги:** `momo-store`, `business`

Дашборд для продуктовых метрик — не технических, а бизнесовых.

### Панели

#### 1. Orders per minute

**PromQL:**
```promql
rate(orders_count{namespace="default"}[5m]) * 60
```

**Что показывает:** сколько заказов в минуту делает система.

**Источник:** counter `orders_count` из бэкенда.

**Единица:** `ops` (operations per second — фактически orders/min).

**Как читать:** сравнить с обычной нагрузкой. Резкое падение — что-то сломалось, резкий рост — маркетинговая активность.

#### 2. Total orders (last 24h)

**PromQL:**
```promql
increase(orders_count{namespace="default"}[24h])
```

**Что показывает:** сколько заказов за последние 24 часа.

**Тип:** Single Stat.

#### 3. Top-10 dumplings by requests

**PromQL:**
```promql
topk(10, rate(dumplings_listing_count{namespace="default"}[5m]))
```

**Что показывает:** топ-10 пельменей по частоте запросов страницы.

**Источник:** counter `dumplings_listing_count` с меткой `id` из бэкенда.

**Legend:** `id={{id}}` — показывает ID товара.

**Как читать:** полезно для маркетинга — какие товары популярны.

---

## 🔧 Momo Store — Infrastructure

**UID:** `momo-store-infrastructure`
**Теги:** `momo-store`, `infra`

Дашборд для инфраструктурных метрик подов Momo Store.

### Панели

#### 1. CPU usage (cores) by pod

**PromQL:**
```promql
sum(rate(container_cpu_usage_seconds_total{namespace="default",pod=~"momo-store-.*",container!="POD"}[5m])) by (pod)
```

**Что показывает:** потребление CPU каждым подом в ядрах (cores).

**Источник:** cAdvisor через `kubelet` (container_cpu_usage_seconds_total).

**Исключение `container!="POD"`:** в Kubernetes у каждого пода есть служебный контейнер `POD` (pause), у которого нет полезной нагрузки. Мы его исключаем.

**Как читать:** сравнивать с лимитами из `values.yaml` (`resources.limits.cpu`). Если под близко к лимиту — стоит увеличить.

#### 2. Memory usage (MiB) by pod

**PromQL:**
```promql
sum(container_memory_working_set_bytes{namespace="default",pod=~"momo-store-.*",container!="POD"}) by (pod) / 1024 / 1024
```

**Что показывает:** потребление памяти каждым подом в MiB.

**Источник:** cAdvisor.

**Как читать:** сравнивать с `resources.limits.memory`. Если под стабильно у лимита — увеличить.

#### 3. Pod restarts (last 1h)

**PromQL:**
```promql
sum(increase(kube_pod_container_status_restarts_total{namespace="default",pod=~"momo-store-.*"}[1h])) by (pod)
```

**Что показывает:** сколько раз каждый под перезапускался за последний час.

**Источник:** `kube-state-metrics`.

**Как читать:**
- `0` — норма.
- `1-2` — если был rollout, нормально.
- `>3` за час — что-то падает, смотрите `kubectl logs`.

#### 4. Network RX/TX (MiB/s)

**PromQL:**
```promql
sum(rate(container_network_receive_bytes_total{namespace="default",pod=~"momo-store-.*"}[5m])) by (pod) / 1024 / 1024
sum(rate(container_network_transmit_bytes_total{namespace="default",pod=~"momo-store-.*"}[5m])) by (pod) / 1024 / 1024
```

**Что показывает:** входящий и исходящий сетевой трафик каждого пода в MiB/s.

**Источник:** cAdvisor.

**Как читать:** фронтенд обычно принимает много трафика (от клиентов) и отдаёт меньше (проксирует в S3). Бэкенд — наоборот, мало принимает, много отдаёт.

---

## 📂 Файл в Helm-чарте

Все три дашборда лежат в одном ConfigMap:

**`k8s/helm/momo-store/templates/monitoring/grafana-dashboards.yaml`**

```yaml
{{- if and .Values.monitoring .Values.monitoring.enabled .Values.monitoring.dashboard .Values.monitoring.dashboard.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "momo-store.fullname" . }}-grafana-dashboards
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "momo-store.labels" . | nindent 4 }}
    grafana_dashboard: "1"
data:
  momo-store-overview.json: |
    { ... JSON дашборда ... }
  momo-store-business.json: |
    { ... JSON дашборда ... }
  momo-store-infrastructure.json: |
    { ... JSON дашборда ... }
{{- end }}
```

**Что важно:**

- **Один ConfigMap — три файла.** Sidecar читает каждый ключ как отдельный дашборд.
- **Метка `grafana_dashboard: "1"`** — обязательна. Без неё sidecar не найдёт ConfigMap.
- **Namespace** — `{{ .Release.Namespace }}` (у вас `default`). Sidecar найдёт благодаря `searchNamespace=ALL`.

---

## 🔄 Как изменить дашборд

### Вариант A — через Helm (правильный)

1. Откройте `k8s/helm/momo-store/templates/monitoring/grafana-dashboards.yaml`.
2. Отредактируйте JSON соответствующего дашборда.
3. `helm upgrade`:

   ```bash
   helm upgrade -i momo-store ./k8s/helm/momo-store \
     -f k8s/helm/momo-store/values.yaml \
     -f k8s/helm/momo-store/values-staging.yaml
   ```

4. Через 30 секунд sidecar обновит файл. Grafana перечитает его.

**Минус:** JSON в YAML сложно редактировать руками. Обычно правят в UI Grafana, потом **экспортируют** результат и вставляют обратно в шаблон.

### Вариант B — через UI + Export

1. Grafana → **Dashboards → Browse** → открыть дашборд.
2. Изменить панели.
3. **Save** → ввести название.
4. **Share → Export → Save to file** → сохранить JSON.
5. Вставить JSON в `grafana-dashboards.yaml` вместо старого.

**Важно:** Grafana sidecar **перезапишет** изменения из UI при следующем `helm upgrade` — потому что дашборд «provisioned». Так что экспорт — обязателен.

### Вариант C — отключить provisioned-флаг

Если нужно редактировать в UI и не терять изменения — **отключите sidecar** для этого дашборда. Но это не рекомендуется, потому что теряется автоматизация.

---

## ➕ Как добавить новый дашборд

1. Создайте JSON в Grafana UI.
2. **Share → Export** → скачайте JSON.
3. Добавьте его как новый ключ в `data` ConfigMap:

   ```yaml
   data:
     momo-store-overview.json: |
       { ... }
     momo-store-business.json: |
       { ... }
     momo-store-infrastructure.json: |
       { ... }
     momo-store-my-new.json: |           # ← новый
       { ... JSON ... }
   ```

4. `helm upgrade` — sidecar подхватит.

---

## 🧪 Проверка

### Что дашборды загрузились

```bash
# ConfigMap создан
kubectl get configmap -n default momo-store-grafana-dashboards

# Внутри — три ключа
kubectl get configmap -n default momo-store-grafana-dashboards \
  -o jsonpath='{.data}' | jq 'keys'
```

Должно вернуть `["momo-store-business.json", "momo-store-infrastructure.json", "momo-store-overview.json"]`.

### Что sidecar их подхватил

```bash
kubectl logs -n monitoring deploy/monitoring-grafana -c grafana-sc-dashboard --tail=30
```

Ищите строки:

```
Writing /tmp/dashboards/momo-store-overview.json (ascii)
Writing /tmp/dashboards/momo-store-business.json (ascii)
Writing /tmp/dashboards/momo-store-infrastructure.json (ascii)
```

### В Grafana

**Dashboards → Browse** → фильтр по тегу `momo-store`. Должны быть все три.

### Если дашбордов нет

1. **Проверьте метку ConfigMap:**
   ```bash
   kubectl get configmap -n default momo-store-grafana-dashboards -o jsonpath='{.metadata.labels}'
   ```
   Должно быть `grafana_dashboard: "1"`.

2. **Проверьте sidecar:**
   ```bash
   kubectl logs -n monitoring deploy/monitoring-grafana -c grafana-sc-dashboard --tail=30
   ```
   Если sidecar пишет `Skipping configmap ...` — проверьте метку и namespace.

3. **Проверьте `searchNamespace=ALL`:**
   ```bash
   kubectl get deploy -n monitoring monitoring-grafana -o yaml | grep -A2 'search-namespace'
   ```
   Должно быть `- --search-namespace=ALL` или подобное. Если нет — добавить в `setup-monitoring.sh`:
   ```bash
   --set grafana.sidecar.dashboards.searchNamespace=ALL
   ```

4. **Рестарт Grafana:**
   ```bash
   kubectl rollout restart deploy -n monitoring monitoring-grafana
   ```

---

## 🎯 Метрики: откуда берутся

Дашборды используют **две категории метрик**:

### 1. Кастомные метрики бэкенда

Экспортирует Go-приложение Momo Store:

| Метрика | Тип | Что |
|---|---|---|
| `response_timing_ms` | Histogram | Время ответа в миллисекундах, по `handler` |
| `response_timing_ms_count` | Counter (авто от histogram) | Общее число запросов |
| `requests_count` | Counter | Число HTTP-запросов |
| `orders_count` | Counter | Число заказов |
| `dumplings_listing_count{id}` | Counter | Число запросов конкретного товара |

Скрейпится Prometheus через `ServiceMonitor` (`momo-store-backend`), endpoint `/metrics` на порту `http`.

### 2. Стандартные метрики Kubernetes

Экспортируют компоненты кластера:

| Метрика | Источник | Что |
|---|---|---|
| `kube_pod_status_ready` | kube-state-metrics | Готовность подов |
| `kube_pod_container_status_restarts_total` | kube-state-metrics | Рестарты |
| `container_cpu_usage_seconds_total` | cAdvisor (kubelet) | CPU подов |
| `container_memory_working_set_bytes` | cAdvisor | RAM подов |
| `container_network_receive_bytes_total` | cAdvisor | Сетевой трафик |

Скрейпятся автоматически через `kube-prometheus-stack`.

---

## 📚 Ссылки

- [Observability: обзор](./readme.md)
- [Алерты](./alerts.md)
- [Grafana Dashboard JSON](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/view-dashboard-json-model/) — формат JSON
- [k8s-sidecar](https://github.com/kiwigrid/k8s-sidecar) — как работает sidecar