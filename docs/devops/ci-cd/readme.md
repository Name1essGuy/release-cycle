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
                                         │ push / merge request / git tag
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
   │ helm    │                     │ + push   │                     │ --atomic │
   └─────────┘                     └──────────┘                     └──────────┘
                                         │                                │
                                         ▼                                ▼
                              ┌────────────────────┐          ┌────────────────────┐
                              │ cr.yandex/...      │          │ Kubernetes cluster │
                              │ momo-store-backend │          │ namespace default  │
                              │ momo-store-frontend│          │ + S3 bucket        │
                              │ :SHA, :latest,     │          │ + ServiceMonitor   │
                              │ :1.2.3, :1.2, :1   │          │ + Grafana ConfigMap│
                              └────────────────────┘          └────────────────────┘
```

---

## 📊 Стадии и джобы

| Стадия | Джоба | Что делает | На каких ветках/тегах |
|---|---|---|---|
| **test** | `test:backend` | `go vet`, `go test` | везде |
| **test** | `test:frontend` | `npm ci`, `npm run lint` | везде |
| **test** | `lint:helm` | `helm lint` | везде |
| **build** | `build:backend` | `docker build` (без push) | feature, fix |
| **build** | `build:frontend-uploader` | `docker build` (без push) | feature, fix |
| **build** | `push:backend` | `docker build` + `docker push` | ci/*, main, теги `v*.*.*` |
| **build** | `push:frontend-uploader` | `docker build` + `docker push` | ci/*, main, теги `v*.*.*` |
| **deploy** | `upload-static:staging` | `aws s3 sync` через frontend-uploader | ci/*, main, теги `v*.*.*` |
| **deploy** | `deploy:staging` | `helm upgrade --atomic` | ci/*, main, теги `v*.*.*` |

> **На git-теге** джобы `build:*` (без push) **не запускаются** — сразу идут `push:*`. Это ожидаемо: на релизе нет смысла собирать образ «на проверку», он сразу пушится.

---

## 🌿 Схема по веткам и тегам

Пайплайн **адаптируется** под тип ветки или git-тега: на feature-ветках — быстрая проверка, на боевых — полный цикл сборки и деплоя, на git-тегах — релиз.

| Триггер | test | build (без push) | push | deploy |
|---|---|---|---|---|
| `feature/*`, `fix/*` | ✅ | ✅ | ❌ | ❌ |
| `ci/*` | ✅ | ❌ | ✅ | ✅ |
| `main` | ✅ | ❌ | ✅ | ✅ |
| git-тег `v1.2.3` | ✅ | ❌ | ✅ | ✅ |

### Пояснение

**`feature/*`, `fix/*`** — обычная разработка. Пайплайн проверяет, что код компилируется, тесты проходят, Dockerfile собирается. Никаких изменений в Container Registry или кластере — безопасно.

**`ci/*`** — ветки для отладки самого пайплайна. Полный цикл, как на `main`. Работает это так же, как на `main`, но без риска сломать боевую ветку.

**`main`** — боевая ветка. Полный пайплайн с публикацией образов в `cr.yandex`, загрузкой статики в S3 и деплоем в Kubernetes. Docker-теги: `${CI_COMMIT_SHORT_SHA}` и `latest`.

**git-тег `v1.2.3`** — релиз. Полный пайплайн с публикацией образов с **семвер-тегами**: `1.2.3`, `1.2`, `1`, `latest`. Деплой в кластер с точным тегом `1.2.3`.

### Что это даёт

- **Разработчики не ждут** долгую сборку с push на каждой feature-ветке.
- **Безопасно** — feature-ветки не могут случайно задеплоить в кластер.
- **Одинаково** — `ci/*` и `main` ведут себя идентично, отладка на `ci/*` переносится на `main` без изменений.
- **Релизы версионируются** — git-теги превращаются в semver Docker-теги.

---

## 🏷 Semver-релизы

### Как выпустить релиз

```bash
# 1. Убедиться, что main актуален
git checkout main
git pull origin main

# 2. Поставить git-тег
git tag v1.2.3

# 3. Запушить
git push origin v1.2.3
```

CI запустится автоматически и:

1. Прогонит `test:*`, `lint:helm`.
2. Соберёт образы и **присвоит им четыре Docker-тега**:
   - `1.2.3` — точная версия;
   - `1.2` — последний patch в минорной ветке;
   - `1` — последний minor в мажорной ветке;
   - `latest` — самый свежий релиз.
3. Запушит все теги в `cr.yandex`.
4. Загрузит статику в S3.
5. Задеплоит в кластер образ с тегом `1.2.3`.

> **Про `latest`:** он перезаписывается на **каждом** релизе и на **каждом** push в `main`/`ci/*`. Это не «последний стабильный релиз», а «последний запушенный образ». Не используйте `latest` в проде — используйте точный semver-тег.

### Как это работает внутри

В `push:*` определяются Docker-теги в зависимости от триггера:

```yaml
if [ -n "$CI_COMMIT_TAG" ]; then
  # git-тег v1.2.3 → 1.2.3, 1.2, 1, latest
  VERSION="${CI_COMMIT_TAG#v}"
  MAJOR_MINOR="${VERSION%.*}"
  MAJOR="${VERSION%%.*}"
  TAGS="${VERSION} ${MAJOR_MINOR} ${MAJOR} latest"
else
  # ветка main/ci → SHA + latest
  TAGS="${CI_COMMIT_SHORT_SHA} latest"
fi
```

Затем для каждого тега добавляется `-t ${IMAGE}:${tag}` при `docker build` и `docker push`.

### Проверка после релиза

```bash
# Список образов и тегов
yc container image list --registry-id crpcti5ji1nf9q4ofu6j

# Конкретные теги
yc container image list --registry-id crpcti5ji1nf9q4ofu6j --format json | jq
```

Ожидаемо: для `momo-store-backend` и `momo-store-frontend-uploader` появились теги `1.2.3`, `1.2`, `1`, `latest` (плюс старые `${SHA}` от предыдущих путей в main).

### Формат git-тега

Только `v1.2.3` (с префиксом `v`, три числа, разделённые точками). Регулярка в правилах: `^v\d+\.\d+\.\d+$`.

Примеры, которые **не** сработают:

- `1.2.3` (без `v`) — не совпадёт с регуляркой.
- `v1.2` (два числа) — не совпадёт.
- `v1.2.3-rc.1` (префикс) — не совпадёт.

### Откат релиза

```bash
# Откатить деплой на предыдущую версию
helm rollback momo-store -n default

# Или вручную задеплоить конкретную версию
helm upgrade -i momo-store ./k8s/helm/momo-store \
  -f values.yaml -f values-staging.yaml \
  --set backend.image.tag=1.2.2 \
  --namespace default
```

---

## 🔄 Автоматический откат при провале деплоя

В `deploy:staging` используется флаг `--atomic` для `helm upgrade`. Полный YAML команды — в разделе [«Связь с observability»](#2-переменная-grafana_smtp_email-передаётся-в-helm-upgrade).

### Как это работает

1. **`--wait`** — Helm ждёт, пока все ресурсы (Deployment, Service, ConfigMap, ServiceMonitor) не станут готовы.
2. **`--atomic`** — если в течение `timeout` поды не стали `Ready` (probes не прошли, под в `CrashLoopBackOff`, образ не скачался), Helm считает релиз неудачным.
3. Helm **автоматически откатывает** релиз к предыдущей успешной ревизии.
4. Джоба падает с ненулевым exit code → пайплайн краснеет.

### Что видно в логах

```
Error: UPGRADE FAILED: release momo-store failed, and has been rolled back due to atomic being set:
Error: context deadline exceeded
```

### Что видно в истории Helm

```bash
helm history momo-store -n default
```

```
REVISION  STATUS      DESCRIPTION
1         superseded  Install complete
2         failed      Upgrade "momo-store" failed: context deadline exceeded
3         deployed    Rollback to 1
```

### Ограничение

`--atomic` **не ловит логические ошибки.** Если под стартанул и отвечает на `/healthz`, но `/api/products` возвращает 500 — Helm считает релиз успешным. Для проверки бизнес-логики — `helm test` после деплоя и `verify.sh` (см. [«Проверка после деплоя»](#-проверка-после-деплоя)).

---

## 🔍 Проверка после деплоя

Пайплайн **не запускает** проверки автоматически — это сделано специально, чтобы не удлинять деплой. Проверить можно **вручную** двумя способами.

### 1. `helm test`

Чарт содержит тестовые поды:

- `templates/tests/test-backend.yaml` — проверяет `GET /health` бэкенда;
- `templates/tests/test-frontend.yaml` — проверяет `GET /healthz` nginx и что статика проксируется как JavaScript (не как HTML).

```bash
helm test momo-store -n default
```

Ожидаемый вывод:

```
NAME: momo-store
LAST DEPLOYED: ...
...
Phase: Succeeded
```

Если `test-frontend` упал с `Content-Type: text/html` на JS-файле — значит `proxy_pass` в nginx-configmap неправильный, и SPA-fallback отдаёт `index.html` вместо статики.

### 2. `verify.sh`

End-to-end проверка через **EXTERNAL-IP** ingress-nginx:

```bash
./infrastructure/scripts/verify.sh
```

Что проверяет:

| Шаг | Что |
|---|---|
| 1 | Поды `backend` и `frontend` в `Running` |
| 2 | `ServiceMonitor/momo-store-backend` и `ConfigMap/momo-store-grafana-dashboards` созданы |
| 3 | `GET /` через EXTERNAL-IP → 200 |
| 4 | `GET /momo-store/js/app.82cde13b.js` → `Content-Type: application/javascript` |
| 5 | `GET /api/products` → JSON с полем `results` |

Если `verify.sh` падает на шаге 4 — nginx отдаёт `index.html` вместо JS. Смотрите `templates/frontend/nginx-configmap.yaml` и `dnsResolver` в `values.yaml`.

---

## 🚀 Триггеры запуска

Пайплайн запускается:

- **Push в ветку** — стадия `test` (на feature/fix) или полный цикл (на ci/main).
- **Push git-тега `v*.*.*`** — полный цикл с semver-тегами.
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
    ├── templates/
    │   ├── monitoring/
    │   │   ├── servicemonitor.yaml       # ServiceMonitor для Prometheus
    │   │   ├── grafana-dashboards.yaml   # ConfigMap с дашбордами
    │   │   └── grafana-alerting.yaml     # ConfigMap с алертами
    │   └── tests/
    │       ├── test-backend.yaml         # helm test для backend
    │       └── test-frontend.yaml        # helm test для frontend
    └── ...
```

`ci/diagnostics.yml` **не подключён** через `include`. Он лежит как резервный инструмент для отладки.

---

## 🔄 Как проходит деплой

### Push в `main` или `ci/*`

1. **`test:backend`** — проверка Go-кода.
2. **`test:frontend`** — lint Vue.js.
3. **`lint:helm`** — валидация Helm-чарта.
4. **`push:backend`** — сборка и публикация образа с тегами `${SHA}`, `latest`.
5. **`push:frontend-uploader`** — то же для uploader.
6. **`upload-static:staging`** — загрузка статики в S3 с использованием образа `${SHA}`.
7. **`deploy:staging`** — `helm upgrade -i momo-store --atomic` с `--set backend.image.tag=${SHA}`.
8. **`kubectl rollout restart deployment/momo-store-frontend`** — nginx **не перечитывает ConfigMap автоматически** при изменении статики в S3. Рестарт гарантирует, что поды фронтенда возьмут актуальный конфиг и начнут отдавать свежие файлы.

### Push git-тега `v1.2.3`

1. **`test:*`** — то же.
2. **`lint:helm`** — то же.
3. **`push:backend`** — сборка и публикация образа с тегами `1.2.3`, `1.2`, `1`, `latest`.
4. **`push:frontend-uploader`** — то же для uploader.
5. **`upload-static:staging`** — загрузка статики с использованием образа `1.2.3`.
6. **`deploy:staging`** — `helm upgrade -i momo-store --atomic` с `--set backend.image.tag=1.2.3`.
7. **`kubectl rollout restart deployment/momo-store-frontend`** — то же.

### После успешного пайплайна

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
    - if: '$CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/'
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
        --set backend.image.tag="${IMAGE_TAG}" \
        --set monitoring.alerting.email="${GRAFANA_SMTP_EMAIL}" \
        --namespace default \
        --atomic \
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
| `diag:monitoring` | CRD `monitoring.coreos.com`, ServiceMonitor, ConfigMap алертов, `GRAFANA_SMTP_EMAIL` |
| `diag:helm-lint` | Валидность Helm-чарта |
| `diag:helm-template` | Рендер Helm-чарта с values |
| `diag:helm-test` | `helm test` — проверка `/health` бэкенда и `/healthz` фронтенда |

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
- [Helm: деплой и troubleshooting](../helm/deployment.md) — проблемы с `helm upgrade` и RBAC
- [Infrastructure](../infrastructure/readme.md) — Terraform-модули
- [Observability](../observability/readme.md) — Prometheus + Grafana, дашборды, алерты
- [Helm-чарт](../helm/readme.md) — описание чарта `momo-store`