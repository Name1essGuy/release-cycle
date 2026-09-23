# Helm-чарт momo-store

## 📋 Описание

Helm-чарт для развёртывания приложения Momo Store в Kubernetes кластере Yandex Cloud.

Включает:

- **backend** — Go-API с метриками и probes.
- **frontend** — Nginx, проксирующий статику из S3, с probes.
- **ingress** — два Ingress-объекта (`api` и `frontend`).
- **monitoring** — ServiceMonitor для Prometheus + ConfigMap'ы для Grafana.
- **tests** — Pod'ы для `helm test` (backend и frontend).

`ingress-nginx` **не входит** в чарт — устанавливается отдельно через `setup-ingress-nginx.sh` (cluster-admin, один раз).

`kube-prometheus-stack` (Prometheus + Grafana) тоже устанавливается **отдельно** через `setup-monitoring.sh`. Чарт `momo-store` только создаёт ресурсы, которые этот стек подхватывает.

---

## 🏗️ Архитектура

```
Пользователь
    │
    ▼
[LoadBalancer Yandex Cloud]                    ← создаётся отдельно (setup-ingress-nginx.sh)
    │
    ▼
[ingress-nginx-controller]                     ← namespace: ingress-nginx
    │
    ├── /api/* ──► [momo-store-backend:8081]    ← namespace: default
    │                     │
    │                     ▼
    │              [Go API :8081, /health, /metrics]
    │                     ▲
    │                     │ scrape /metrics
    │                     │ (ServiceMonitor)
    │                     │
    │              [Prometheus]                 ← namespace: monitoring
    │
    └── /*     ──► [momo-store-frontend:80]
                          │
                          ├── /healthz   ──► 200 OK (для probes и helm test)
                          ├── /          ──► [S3: momo-store/index.html]
                          ├── /js/*      ──► [S3: momo-store/js/*]
                          ├── /css/*     ──► [S3: momo-store/css/*]
                          └── /*         ──► [S3: momo-store/index.html]  (SPA fallback)

[Grafana] ← sidecar ← ConfigMap/momo-store-grafana-dashboards (grafana_dashboard=1)
                     ← ConfigMap/momo-store-grafana-alerting   (grafana_alert=1)
```

Подробнее — в [architecture.md](./architecture.md).

---

## 📁 Структура чарта

```
momo-store/
├── Chart.yaml
├── values.yaml
├── values-staging.yaml
├── values-prod.yaml
└── templates/
    ├── _helpers.tpl
    ├── ingress.yaml
    ├── frontend/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── nginx-configmap.yaml
    ├── backend/
    │   ├── deployment.yaml
    │   └── service.yaml
    ├── monitoring/
    │   ├── servicemonitor.yaml       # ServiceMonitor для Prometheus
    │   ├── grafana-dashboards.yaml   # ConfigMap с тремя дашбордами
    │   ├── grafana-alerting.yaml     # ConfigMap с алертами + contact point
    │   └── prometheusrule.yaml       # CRD с алертами (legacy, для UI Grafana)
    └── tests/
        ├── test-backend.yaml         # helm test для backend
        └── test-frontend.yaml        # helm test для frontend
```

---

## 🔧 Предварительные требования

| Инструмент | Версия |
|---|---|
| Helm | >= 3.12 |
| kubectl | >= 1.28 |
| Доступ к кластеру | kubeconfig |
| Prometheus | установлен через `setup-monitoring.sh` (для scrape метрик) |
| Grafana | установлена через `setup-monitoring.sh` (для дашбордов и алертов) |

Чарт можно установить и **без** monitoring — тогда не будет метрик и дашбордов, но приложение будет работать. Для отключения установите `monitoring.enabled: false`.

> **`ingress-nginx` обязателен.** Без него Ingress-объекты из чарта не будут работать: у них `ingressClassName: nginx`. Установить — `setup-ingress-nginx.sh staging`.

---

## 🚀 Быстрый старт

```bash
helm upgrade -i momo-store ./ \
  -f values.yaml \
  -f values-staging.yaml \
  --set monitoring.alerting.email="${GRAFANA_SMTP_EMAIL}" \
  --namespace default \
  --atomic \
  --wait --timeout 5m
```

**Ключевые флаги:**

- `--set monitoring.alerting.email` — обязателен при `monitoring.enabled=true`.
- `--atomic` — автоматический откат при провале деплоя.
- `--wait --timeout 5m` — дождаться готовности подов.

**Про `--atomic`:** если поды не станут `Ready` за 5 минут (probes не прошли, под в `CrashLoopBackOff`, образ не скачался), Helm автоматически откатит релиз к предыдущей успешной ревизии. Джоба упадёт. Подробнее — в [CI/CD: автоматический откат](../ci-cd/readme.md#-автоматический-откат-при-провале-деплоя).

> **`--atomic` не ловит логические ошибки.** Если под стартанул и отвечает на probes, но `/api/products` возвращает 500 — Helm считает релиз успешным. Для проверки бизнес-логики — `helm test` и `verify.sh` (см. [«Проверки работоспособности»](#-проверки-работоспособности)).

---

## 🩺 Проверки работоспособности

В чарте три уровня проверок.

### 1. Probes (постоянно)

У **backend** и **frontend** настроены `livenessProbe` и `readinessProbe`.

| Компонент | Путь | Порт | Зачем |
|---|---|---|---|
| backend | `/health` | 8081 | Проверяет, что Go-API отвечает |
| frontend | `/healthz` | 80 | Проверяет, что nginx жив. **Не ходит в S3** — просто возвращает `200 ok` |

Probes описываются в `values.yaml`:

```yaml
frontend:
  probes:
    liveness:
      path: /healthz
      port: 80
      initialDelaySeconds: 10
      periodSeconds: 10
    readiness:
      path: /healthz
      port: 80
      initialDelaySeconds: 5
      periodSeconds: 5
```

**Что даёт:**

- Если nginx завис — `livenessProbe` упадёт, kubelet перезапустит контейнер.
- Если nginx не готов принимать трафик — `readinessProbe` упадёт, под будет убран из Service endpoints.
- `--atomic` в `helm upgrade` ловит провал probes — если под не станет `Ready`, Helm откатит релиз.

> **`/healthz` для frontend** — статический ответ nginx. Он **не ходит в S3**, поэтому не зависит от доступности Object Storage. Если S3 недоступен — probes всё равно пройдут, но статика не загрузится. Это осознанно: недоступность S3 не должна ронять поды nginx.

### 2. `helm test` (по запросу)

Запускается вручную:

```bash
helm test momo-store -n default --logs
```

Проверяет:

| Test | Что проверяет |
|---|---|
| `test-backend` | `GET /health` на сервисе backend отвечает 200 |
| `test-frontend` | `GET /healthz` отвечает 200 и `GET /momo-store/js/...` отдаётся как JavaScript (не HTML) |

`test-frontend` ловит классическую ошибку: если nginx возвращает `index.html` вместо JS из-за неправильного `proxy_pass` — тест упадёт с `Content-Type: text/html`.

> **`helm test` не запускается автоматически** в пайплайне. Чтобы прогнать после деплоя — вручную или через `diag:helm-test` из `ci/diagnostics.yml` (см. [CI/CD: диагностика](../ci-cd/diagnostics.md#-diaghelm-test)).

### 3. `verify.sh` (по запросу, снаружи)

Скрипт `infrastructure/scripts/verify.sh` проверяет всё, что не видит Helm: ingress, LB, внешний IP.

```bash
cd infrastructure
./scripts/verify.sh
```

Проверяет:

- Поды backend и frontend `Ready`.
- ServiceMonitor и ConfigMap'ы мониторинга созданы.
- Сайт открывается по `EXTERNAL-IP`.
- Статика проксируется как JS.
- `/api/products` возвращает JSON.

---

## 📊 Мониторинг

Чарт создаёт следующие ресурсы для observability:

| Ресурс | Метка | Что даёт |
|---|---|---|
| `ServiceMonitor/momo-store-backend` | `release: monitoring` | Prometheus скрейпит `/metrics` бэкенда |
| `ConfigMap/momo-store-grafana-dashboards` | `grafana_dashboard: "1"` | Sidecar Grafana загружает три дашборда |
| `ConfigMap/momo-store-grafana-alerting` | `grafana_alert: "1"` | Sidecar Grafana загружает алерты и contact point |
| `PrometheusRule/momo-store-alerts` | `release: monitoring` | Правила для UI Grafana (legacy, опционально) |

**Проверка после деплоя:**

```bash
# ServiceMonitor создан
kubectl get servicemonitor -n default | grep momo-store

# ConfigMap с дашбордами
kubectl get configmap -n default momo-store-grafana-dashboards

# ConfigMap с алертами
kubectl get configmap -n monitoring momo-store-grafana-alerting
```

> **`ConfigMap/momo-store-grafana-alerting` создаётся в namespace `monitoring`**, а не в namespace релиза (`default`). Это значит, что у `ci-deployer` должны быть права на создание ConfigMap в `monitoring` — иначе `helm upgrade` упадёт с `Forbidden`. Подробнее — в [CI/CD: переменные](../ci-cd/variables.md#-kube_config_staging).

Подробнее:

- [Observability: обзор](../observability/readme.md)
- [Observability: дашборды](../observability/dashboards.md)
- [Observability: алерты](../observability/alerts.md)

---

## 🧹 Удаление

```bash
helm uninstall momo-store -n default
```

**Что остаётся:**

- `PrometheusRule/momo-store-alerts` — **останется**, потому что Helm не удаляет CRD без аннотации. Удалить вручную:
  ```bash
  kubectl delete prometheusrule momo-store-alerts -n default
  ```
- Секрет `ycr-secret` — **останется** (создан вручную).

Всё остальное (ServiceMonitor, ConfigMap'ы, Deployment, Service, Ingress) — удалится вместе с релизом. Подробнее — в [deployment.md](./deployment.md#-удаление).

---

## 📚 Документация

- [Архитектура](./architecture.md) — компоненты чарта и схема потоков
- [Параметры values](./values-reference.md) — все ключи `values.yaml`
- [Деплой и обновление](./deployment.md) — установка, проверка, откат, troubleshooting
- [CI/CD: пайплайн](../ci-cd/readme.md) — как чарт деплоится из GitLab CI
- [Observability](../observability/readme.md) — Prometheus + Grafana, дашборды, алерты
