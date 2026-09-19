# CI/CD пайплайн

## 📋 Описание

Проект использует **GitLab CI/CD** для автоматической сборки, публикации и деплоя приложения Momo Store. Пайплайн описан в `.gitlab-ci.yml` в корне репозитория и состоит из трёх стадий: **test**, **build**, **deploy**.

Дополнительно в `ci/diagnostics.yml` лежат диагностические джобы — они **не подключены** к основному пайплайну и запускаются только вручную при отладке.

Раннеры работают в Yandex Cloud (ВМ `staging-runner`), созданной через Terraform-модуль `gitlab-runner`. Все джобы запускаются в Docker-контейнерах через `docker executor` с `dind`.

---

## 🏗 Общая схема

```
             ┌───────────────────────────────────────────────────────────────┐
             │ GitLab project: Name1ess_One/momo-store                       │
             └───────────────────────────┬───────────────────────────────────┘
                                         │ push / merge request
                                         ▼
             ┌───────────────────────────────────────────────────────────────┐
             │ .gitlab-ci.yml                                                │
             │                                                               │
             │  stages: test → build → deploy                                │
             └───────────────────────────┬───────────────────────────────────┘
                                         │
                                         ▼
             ┌───────────────────────────────────────────────────────────────┐
             │ GitLab Runner: staging-runner (Sl-vYK7CX)                     │
             │ Tags: docker, staging                                         │
             │ Executor: docker + dind (privileged = true)                   │
             └───────────────────────────┬───────────────────────────────────┘
                                         │
        ┌────────────────────────────────┼────────────────────────────────┐
        │                                │                                │
        ▼                                ▼                                ▼
   ┌─────────┐                     ┌──────────┐                     ┌──────────┐
   │  test   │                     │  build   │                     │  deploy  │
   │         │                     │          │                     │          │
   │ backend │                     │ backend  │                     │ S3 static│
   │ frontend│                     │ frontend │                     │ helm up  │
   │ helm    │                     │ + push   │                     │          │
   └─────────┘                     └──────────┘                     └──────────┘
                                         │                                │
                                         ▼                                ▼
                              ┌────────────────────┐          ┌────────────────────┐
                              │ cr.yandex/...      │          │ Kubernetes cluster │
                              │ momo-store-backend │          │ namespace default  │
                              │ momo-store-frontend│          │ + S3 bucket        │
                              └────────────────────┘          │ + ServiceMonitor   │
                                                              │ + Grafana ConfigMap│
                                                              └────────────────────┘
```

---

## 📊 Стадии и джобы

| Стадия | Джоба | Что делает | На каких ветках |
|---|---|---|---|
| **test** | `test:backend` | `go vet`, `go test` | везде |
| **test** | `test:frontend` | `npm ci`, `npm run lint` | везде |
| **test** | `lint:helm` | `helm lint` | везде |
| **build** | `build:backend` | `docker build` (без push) | feature, fix |
| **build** | `build:frontend-uploader` | `docker build` (без push) | feature, fix |
| **build** | `push:backend` | `docker build` + `docker push` | ci/*, main |
| **build** | `push:frontend-uploader` | `docker build` + `docker push` | ci/*, main |
| **deploy** | `upload-static:staging` | `aws s3 sync` через frontend-uploader | ci/*, main |
| **deploy** | `deploy:staging` | `helm upgrade` в кластере | ci/*, main |

---

## 🌿 Схема по веткам

Пайплайн **адаптируется** под тип ветки: на feature-ветках — быстрая проверка, на боевых — полный цикл сборки и деплоя.

| Ветка | test | build (без push) | push | deploy |
|---|---|---|---|---|
| `feature/*`, `fix/*` | ✅ | ✅ | ❌ | ❌ |
| `ci/*` | ✅ | ❌ | ✅ | ✅ |
| `main` | ✅ | ❌ | ✅ | ✅ |

### Пояснение

**`feature/*`, `fix/*`** — обычная разработка. Пайплайн проверяет, что код компилируется, тесты проходят, Dockerfile собирается. Никаких изменений в Container Registry или кластере — безопасно.

**`ci/*`** — ветки для отладки самого пайплайна. Полный цикл, как на `main`. Работает это так же, как на `main`, но без риска сломать боевую ветку.

**`main`** — боевая ветка. Полный пайплайн с публикацией образов в `cr.yandex`, загрузкой статики в S3 и деплоем в Kubernetes.

### Что это даёт

- **Разработчики не ждут** долгую сборку с push на каждой feature-ветке.
- **Безопасно** — feature-ветки не могут случайно задеплоить в кластер.
- **Одинаково** — `ci/*` и `main` ведут себя идентично, отладка на `ci/*` переносится на `main` без изменений.

---

## 🚀 Триггеры запуска

Пайплайн запускается:

- **Push в любую ветку** — только стадия `test` (на feature/fix) или полный цикл (на ci/main).
- **Merge request** — стадия `test`. Результаты видны в MR.
- **Вручную** — через GitLab UI → **CI/CD → Pipelines → Run pipeline** (например, для диагностики).

---

## 🔐 Переменные CI/CD

Подробно — в [variables.md](./variables.md). Кратко:

| Переменная | Назначение | Masked | Protected |
|---|---|---|---|
| `YC_SA_KEY_JSON` | Авторизация в `cr.yandex` (base64 от key.json) | ✅ | ❌ |
| `AWS_ACCESS_KEY_ID` | Доступ к S3 | ✅ | ❌ |
| `AWS_SECRET_ACCESS_KEY` | Доступ к S3 | ✅ | ❌ |
| `S3_BUCKET` | Имя S3-бакета со статикой | ❌ | ❌ |
| `KUBE_CONFIG_STAGING` | Kubeconfig для деплоя (base64) | ✅ | ❌ |
| `GRAFANA_SMTP_EMAIL` | Email для алертов Grafana | ❌ | ❌ |

**Важно:** флаг `Protected` **снят** со всех переменных, потому что деплой может запускаться из ветки `ci/*`, а она не protected. Если хотите защитить `main`, включите `Protected` — но тогда `ci/*` не сможет использовать эти переменные.

---

## 📁 Структура файлов

```
momo-store/
├── .gitlab-ci.yml              # Основной пайплайн (test → build → deploy)
├── ci/
│   └── diagnostics.yml         # Диагностические джобы (не подключены)
├── services/
│   ├── backend/                # Go-API
│   │   └── Dockerfile
│   └── frontend/               # Vue.js + uploader
│       └── Dockerfile
└── k8s/helm/momo-store/        # Helm-чарт
    └── templates/
        └── monitoring/
            ├── servicemonitor.yaml       # ServiceMonitor для Prometheus
            ├── grafana-dashboards.yaml   # ConfigMap с дашбордами
            └── grafana-alerting.yaml     # ConfigMap с алертами
```

`ci/diagnostics.yml` **не подключён** через `include`. Он лежит как резервный инструмент для отладки.

---

## 🔄 Как проходит деплой

Последовательность на push в `main`:

1. **`test:backend`** — проверка Go-кода.
2. **`test:frontend`** — lint Vue.js.
3. **`lint:helm`** — валидация Helm-чарта.
4. **`push:backend`** — сборка и публикация образа `cr.yandex/.../momo-store-backend:${SHA}`.
5. **`push:frontend-uploader`** — сборка и публикация образа `cr.yandex/.../momo-store-frontend-uploader:${SHA}`.
6. **`upload-static:staging`** — запуск `frontend-uploader` для загрузки статики в S3 (`s3://momo-store-frontend/momo-store/`).
7. **`deploy:staging`** — `helm upgrade -i momo-store` с тегом образа `${CI_COMMIT_SHORT_SHA}` и email для алертов.

После успешного пайплайна:

- S3 содержит свежую статику.
- В кластере — обновлённые поды `momo-store-frontend` и `momo-store-backend`.
- Ingress-nginx маршрутизирует трафик на эти поды.
- Prometheus скрейпит `/metrics` бэкенда (через ServiceMonitor).
- Grafana показывает дашборды и может отправлять алерты.

---

## 🔭 Связь с observability

CI/CD и observability связаны в **двух точках**.

### 1. Деплой чарта `momo-store` создаёт ресурсы для мониторинга

При `helm upgrade -i momo-store` в стадии **deploy** создаются:

| Ресурс | Метка | Что даёт |
|---|---|---|
| `ServiceMonitor/momo-store-backend` | `release: monitoring` | Prometheus начинает скрейпить `/metrics` бэкенда |
| `ConfigMap/momo-store-grafana-dashboards` | `grafana_dashboard: "1"` | Sidecar Grafana загружает три дашборда |
| `ConfigMap/momo-store-grafana-alerting` | `grafana_alert: "1"` | Sidecar Grafana загружает contact point, алерты и notification policies |

Всё это — **часть Helm-чарта**, а не отдельный шаг CI. Если чарт задеплоен — метрики и алерты работают. CI ничего дополнительно настраивать не нужно.

**Проверка после деплоя:**

```bash
# ServiceMonitor создан
kubectl get servicemonitor -n default | grep momo-store

# ConfigMap с дашбордами
kubectl get configmap -n default momo-store-grafana-dashboards

# ConfigMap с алертами
kubectl get configmap -n monitoring momo-store-grafana-alerting
```

### 2. Переменная `GRAFANA_SMTP_EMAIL` передаётся в `helm upgrade`

Чтобы contact point `gmail-alerts` содержал **реальный email**, а не placeholder, в `deploy:staging` передаётся `--set monitoring.alerting.email`:

```yaml
deploy:staging:
  stage: deploy
  image: alpine:3.20
  tags: [docker, staging]
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
    - if: '$CI_COMMIT_BRANCH =~ /^ci\//'
  environment:
    name: staging
  before_script:
    - apk add --no-cache helm kubectl
    - echo "$KUBE_CONFIG_STAGING" | base64 -d > /tmp/kubeconfig
    - export KUBECONFIG=/tmp/kubeconfig
  script:
    - |
      helm upgrade -i momo-store "${HELM_CHART_DIR}" \
        -f "${HELM_CHART_DIR}/values.yaml" \
        -f "${HELM_CHART_DIR}/values-staging.yaml" \
        --set backend.image.tag="${CI_COMMIT_SHORT_SHA}" \
        --set monitoring.alerting.email="${GRAFANA_SMTP_EMAIL}" \
        --namespace default \
        --wait --timeout 5m
```

**Без `--set monitoring.alerting.email`** в `ConfigMap/momo-store-grafana-alerting` попадёт пустое значение, и `helm upgrade` **упадёт** с ошибкой:

```
Error: UPGRADE FAILED: execution error at (momo-store/templates/monitoring/grafana-alerting.yaml:...):
monitoring.alerting.email is required when monitoring.alerting.enabled=true
```

Это защита от случайного деплоя без email.

### Связанные компоненты

| Компонент | Где описан | Как связан с CI/CD |
|---|---|---|
| Prometheus + Grafana | [observability/readme.md](../observability/readme.md) | Устанавливается `setup-monitoring.sh`, деплой в кластер |
| Дашборды | [observability/dashboards.md](../observability/dashboards.md) | Деплоятся через ConfigMap из чарта `momo-store` |
| Алерты | [observability/alerts.md](../observability/alerts.md) | Деплоятся через ConfigMap из чарта `momo-store` |

---

## 🧩 Связанные компоненты

| Компонент | Где описан | Как связан с CI/CD |
|---|---|---|
| GitLab Runner | [gitlab-runner.md](../infrastructure/gitlab-runner.md) | Исполняет джобы, установлен через Terraform |
| Container Registry | [bootstrap.md](../infrastructure/bootstrap.md) | Хранит образы, `push:*` пушит сюда |
| Kubernetes cluster | [kubernetes-cluster.md](../infrastructure/kubernetes-cluster.md) | `deploy:staging` деплоит сюда |
| RBAC для CI | [infrastructure/readme.md](../infrastructure/readme.md) → «CI/CD RBAC» | `ci-deployer` — SA, под которым работает деплой |
| Ingress-nginx | [infrastructure/readme.md](../infrastructure/readme.md) → «Ingress-Nginx» | Устанавливается отдельно, не через CI |
| Monitoring | [infrastructure/readme.md](../infrastructure/readme.md) → «Monitoring» | Устанавливается отдельно, не через CI |
| Helm-чарт | [helm/readme.md](../helm/readme.md) | Используется в `deploy:staging` |

---

## 🛠 Диагностика

Отдельный набор диагностических джоб лежит в `ci/diagnostics.yml`. Он **не подключён** к основному пайплайну. Чтобы запустить:

1. Создать временную ветку `ci/run-diagnostics` от `ci/pipeline-dev`.
2. Скопировать `ci/diagnostics.yml` в `.gitlab-ci.yml` (или использовать GitLab UI для временного переключения).
3. Push → запустится диагностический пайплайн.

Что проверяет каждая `diag:*`-джоба:

| Джоба | Что проверяет |
|---|---|
| `diag:network` | Сеть до GitLab, cr.yandex, S3, registry.k8s.io, docker.io |
| `diag:dind` | Docker-in-docker работает |
| `diag:registry-login` | Авторизация в `cr.yandex` |
| `diag:s3` | Доступ к S3 (list, upload, delete) |
| `diag:kubectl` | Доступ к Kubernetes кластеру |
| `diag:helm-lint` | Валидность Helm-чарта |
| `diag:helm-template` | Рендер Helm-чарта с values |

Подробнее — в [diagnostics.md](./diagnostics.md).

---

## ⚡ Ускорения

Пайплайн использует несколько приёмов для ускорения:

- **Кэш Go** (`GOPATH`, `GOCACHE`, `GOMODCACHE`) — в `test:backend`.
- **Кэш npm** (`node_modules`, `.npm`) — в `test:frontend`.
- **Кэш Docker-слоёв** через `--cache-from` + `BUILDKIT_INLINE_CACHE=1` — в `push:*`.
- **`interruptible: true`** — при новом push старые пайплайны отменяются.
- **`needs`** — `deploy:staging` и `upload-static:staging` стартуют сразу после своих зависимостей, не дожидаясь всех джоб стадии `build`.

---

## 📚 Документация

- [Переменные](./variables.md) — какие переменные нужны и откуда брать
- [Диагностика](./diagnostics.md) — как запускать `diag:*`-джобы
- [Infrastructure](../infrastructure/readme.md) — Terraform-модули
- [Observability](../observability/readme.md) — Prometheus + Grafana, дашборды, алерты
- [Helm-чарт](../helm/readme.md) — описание чарта `momo-store`