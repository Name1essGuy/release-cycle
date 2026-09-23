# Архитектура чарта momo-store

## Компоненты

### Backend

- **Образ**: `cr.yandex/.../momo-store-backend`
- **Порт**: 8081
- **Health**: `/health`
- **API**: `/products`, `/categories`
- **Метрики**: `/metrics` (Prometheus format)
- **Probes**: `livenessProbe` и `readinessProbe` на `/health`
- **Провижининг**: `templates/backend/deployment.yaml`, `templates/backend/service.yaml`

### Frontend

- **Образ**: `nginx:1.27-alpine`
- **Порт**: 80
- **Назначение**: проксирование статики из S3 + SPA-роутинг
- **Health**: `/healthz` — статический ответ nginx, **не ходит в S3**
- **Probes**: `livenessProbe` и `readinessProbe` на `/healthz`
- **Конфиг**: ConfigMap `momo-store-frontend-nginx`
- **Провижининг**: `templates/frontend/deployment.yaml`, `templates/frontend/service.yaml`, `templates/frontend/nginx-configmap.yaml`

> **Почему `/healthz` не ходит в S3.** Если S3 недоступен, nginx всё равно должен считаться живым — иначе kubelet перезапустит поды, и они уйдут в `CrashLoopBackOff`. Недоступность S3 — это проблема статики, а не nginx. Поэтому `/healthz` — статический `return 200 "ok\n"`.

### Ingress

- **Тип**: ingress-nginx (устанавливается **отдельно**, `setup-ingress-nginx.sh`)
- **Два объекта**:
  - `momo-store-api` — `/api(/|$)(.*)` → backend:8081 с `rewrite-target: /$2`;
  - `momo-store-frontend` — `/` → frontend:80 **без** rewrite.
- **Провижининг**: `templates/ingress.yaml`

### LoadBalancer

- **Тип**: Yandex Cloud NLB (EXTERNAL)
- **Порты**: 80, 443
- **Создаётся**: ingress-nginx контроллером (не чартом `momo-store`)
- **SG**: аннотация `yandex.cloud/security-group-ids` на сервисе `ingress-nginx-controller`

### Monitoring

- **ServiceMonitor/momo-store-backend** — говорит Prometheus скрейпить `/metrics` бэкенда.
- **ConfigMap/momo-store-grafana-dashboards** (namespace `default`) — три дашборда для Grafana.
- **ConfigMap/momo-store-grafana-alerting** (namespace `monitoring`) — contact point, четыре алерта, notification policy.
- **PrometheusRule/momo-store-alerts** (namespace `default`) — CRD с алертами (legacy, идёт только в UI Grafana).
- **Провижининг**: `templates/monitoring/*.yaml`

> **ConfigMap алертов — в namespace `monitoring`,** а не в namespace релиза. Это сделано потому, что sidecar `grafana-sc-alerts` ищет ConfigMap с меткой `grafana_alert=1` в namespace `monitoring`. Дашборды, наоборот, лежат в `default` — их sidecar ищет во **всех** namespace (`searchNamespace=ALL`).

### Tests

- **Pod/test-backend** — `GET /health` на сервисе backend.
- **Pod/test-frontend** — `GET /healthz` и проверка, что JS-файл отдаётся как JavaScript (не HTML).
- **Провижининг**: `templates/tests/*.yaml`
- **Запуск**: `helm test momo-store -n default`

---

## Схема потоков

```
┌──────────────┐
│ Пользователь │
└──────┬───────┘
       │ HTTPS
       ▼
┌────────────────────────────┐
│ LoadBalancer Yandex Cloud  │   ← создаётся ingress-nginx контроллером
└──────────┬─────────────────┘
           │ NodePort
           ▼
┌────────────────────────────────────────────────────────┐
│ ingress-nginx-controller (namespace: ingress-nginx)    │
│                                                        │
│   Ingress-правила:                                     │
│     /api(/|$)(.*) → backend:8081 (rewrite /$2)         │
│     /             → frontend:80                        │
└───────────┬────────────────────────┬───────────────────┘
            │                        │
   /api/*   │                        │  /*
            ▼                        ▼
┌─────────────────────┐   ┌─────────────────────────┐
│ Service/backend     │   │ Service/frontend        │
│ :8081 (ClusterIP)   │   │ :80 (ClusterIP)         │
└──────────┬──────────┘   └──────────┬──────────────┘
           │                          │
           ▼                          ▼
┌─────────────────────┐   ┌─────────────────────────┐
│ Deployment/backend  │   │ Deployment/frontend     │
│ Go API :8081        │   │ Nginx :80               │
│ /health, /metrics   │   │ /healthz (static)       │
└──────────┬──────────┘   └──────────┬──────────────┘
           │                          │
           │ scrape                   │ proxy_pass HTTPS
           │ /metrics                 │ storage.yandexcloud.net
           │                          │
           ▼                          ▼
┌─────────────────────┐   ┌─────────────────────────┐
│ Prometheus          │   │ S3: momo-store-frontend │
│ (namespace:         │   │  prefix: momo-store/    │
│  monitoring)        │   │                         │
│                     │   │  index.html             │
│ ServiceMonitor ─────┘   │  js/...                 │
│                         │  css/...                │
│                         │  img/...                │
│                         └─────────────────────────┘
│
└──► Grafana ← sidecar ← ConfigMap/momo-store-grafana-dashboards (default)
                       ← ConfigMap/momo-store-grafana-alerting  (monitoring)
             │
             └──► Email (Gmail) — алерты
```

---

## Особенности

### S3-статика

- Все статические файлы (`js`, `css`, `img`) лежат в Object Storage.
- Frontend-Nginx проксирует их через `proxy_pass` в S3.
- Префикс `momo-store/` **уже в URI от браузера**, поэтому `$s3_prefix` **не добавляется** к `$request_uri`.
- Для `location = /` используется `$s3_prefix/index.html` — потому что браузер просит `/`.
- `resolver` — ClusterIP kube-dns из `values.frontend.dnsResolver`.

### DNS-резолвинг

- Nginx использует `resolver <ClusterIP kube-dns>` для runtime-резолвинга `storage.yandexcloud.net`.
- ClusterIP kube-dns **меняется при пересоздании кластера** — надо обновлять в `values-<env>.yaml`.
- `proxy_pass` использует переменную `$s3_upstream` — отложенный резолвинг, чтобы nginx не падал при старте, если DNS не готов.

### rewrite-target

- Аннотация `nginx.ingress.kubernetes.io/rewrite-target: /$2` применяется **только** к Ingress `momo-store-api`.
- Для frontend используется **отдельный** Ingress без rewrite.
- Если бы rewrite был один на весь Ingress, он бы ломал пути к статике: `/momo-store/js/...` → `/`.

### Провижининг мониторинга

- **Дашборды** — ConfigMap с меткой `grafana_dashboard=1` в namespace `default`. Sidecar Grafana ищет такие ConfigMap во **всех** namespace (`searchNamespace=ALL`) и загружает.
- **Алерты** — ConfigMap с меткой `grafana_alert=1` в namespace `monitoring`. Тот же механизм, другой sidecar (`grafana-sc-alerts`).
- **`monitoring.alerting.email`** — обязательный параметр. Передаётся при `helm upgrade` через `--set`, попадает в ConfigMap `momo-store-grafana-alerting`. Без него `helm upgrade` падает с `fail`.

> **Разное namespace для дашбордов и алертов** — исторически так сложилось: `searchNamespace=ALL` настроен только для dashboards-sidecar, а alerts-sidecar смотрит только в свой namespace. Если хотите единообразия — можно либо поменять настройки sidecar, либо создавать оба ConfigMap в одном namespace.

### Что **не** входит в чарт

- **`ingress-nginx`** — устанавливается отдельно (`setup-ingress-nginx.sh`).
- **Prometheus + Grafana** — устанавливаются отдельно (`setup-monitoring.sh`).
- **LoadBalancer** — создаётся автоматически YC-контроллером при установке ingress-nginx.
- **S3-бакет** — создаётся в bootstrap-модуле Terraform.
- **`ycr-secret`** — создаётся вручную или через CI (не в чарте).

---

## Зависимости

Чарт **не имеет** зависимостей от других Helm-чартов. Всё, что ему нужно (Prometheus, Grafana, ingress-nginx), устанавливается отдельно, до или после деплоя чарта.

`Chart.yaml` — без `dependencies`.

---

## Связанные документы

- [README чарта](./readme.md) — быстрый старт, проверки, удаление
- [Values reference](./values-reference.md) — все ключи `values.yaml`
- [Deployment](./deployment.md) — установка, troubleshooting
- [CI/CD](../ci-cd/readme.md) — как чарт деплоится из GitLab CI
- [Observability](../observability/readme.md) — Prometheus + Grafana, дашборды, алерты