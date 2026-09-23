# Momo Store

Учебный проект — интернет-магазин пельменей. Демонстрирует полный цикл разработки и эксплуатации: от локального `docker-compose` до production-grade деплоя в Yandex Cloud с CI/CD, мониторингом и алертами.

---

## 📋 Что внутри

| Компонент | Стек | Назначение |
|---|---|---|
| **Backend** | Go | REST API: `/products`, `/categories`, `/orders`, `/auth`. Метрики Prometheus на `/metrics`. |
| **Frontend** | Vue.js 3 + TypeScript | SPA-каталог. Статика собирается и загружается в S3. |
| **Frontend-uploader** | Alpine + AWS CLI | Одноразовый контейнер: синхронизирует статику из образа в S3. |
| **Infrastructure** | Terraform | VPC, managed Kubernetes, GitLab Runner, S3, Container Registry. |
| **CI/CD** | GitLab CI | Тесты, сборка, push в `cr.yandex`, деплой через Helm. Semver-релизы через git-теги. |
| **Helm-чарт** | Helm 3 | Backend, frontend, Ingress, ServiceMonitor, Grafana-дашборды и алерты. |
| **Observability** | kube-prometheus-stack | Prometheus + Grafana + node-exporter + kube-state-metrics. Алерты — через Grafana Alerting. |

---

## 🏗 Архитектура

```
                              ┌─────────────────────┐
                              │     Пользователь    │
                              └──────────┬──────────┘
                                         │ HTTPS
                                         ▼
                              ┌─────────────────────┐
                              │  Yandex Cloud NLB   │
                              └──────────┬──────────┘
                                         │
                                         ▼
                              ┌─────────────────────┐
                              │   ingress-nginx     │  namespace: ingress-nginx
                              └──────┬────────┬─────┘
                                     │        │
                            /api/*   │        │  /*
                                     ▼        ▼
                    ┌──────────────────┐  ┌──────────────────┐
                    │ momo-store-      │  │ momo-store-      │  namespace: default
                    │ backend:8081     │  │ frontend:80      │
                    │ Go API, /metrics │  │ nginx → S3       │
                    └────────┬─────────┘  └────────┬─────────┘
                             │                     │
                             │ scrape              │ proxy_pass
                             │ /metrics            │ storage.yandexcloud.net
                             ▼                     ▼
                    ┌──────────────────┐  ┌──────────────────┐
                    │   Prometheus     │  │  S3: статика     │  namespace: monitoring
                    │   + Grafana      │  │  momo-store/...  │
                    │   namespace:     │  └──────────────────┘
                    │   monitoring     │
                    └──────────────────┘
```

**Ключевые решения:**

- **`ingress-nginx` и `monitoring` — инфраструктурные компоненты**, ставятся админом один раз. Чарт `momo-store` их не создаёт.
- **CI имеет ограниченный RBAC** — `ci-deployer` в namespace `default` + `monitoring`. Cluster-wide ресурсы CI не трогает.
- **Статика — в S3.** Frontend — это nginx, который проксирует запросы в Object Storage. Никаких файлов внутри пода.
- **Алерты — через Grafana Alerting.** Alertmanager отключён.
- **Релизы — semver через git-теги.** `git tag v1.2.3 && git push origin v1.2.3` → Docker-теги `1.2.3`, `1.2`, `1`, `latest`.

---

## 🚀 Быстрый старт (локально)

### Предварительные требования

| Инструмент | Версия |
|---|---|
| Docker | последняя |
| Docker Compose | v2 |
| Go (для локальной разработки backend) | ≥ 1.21 |
| Node.js (для локальной разработки frontend) | ≥ 20 |

### Запуск

```bash
git clone <repo-url>
cd momo-store

# Backend + frontend + nginx
docker compose up --build
```

После сборки:

| Сервис | URL |
|---|---|
| Frontend | http://localhost:8080 |
| Backend API | http://localhost:8081/api/products |
| Backend health | http://localhost:8081/health |
| Backend metrics | http://localhost:8081/metrics |

### Разработка

**Backend:**

```bash
cd services/backend
go mod download
go run cmd/api/main.go
```

**Frontend:**

```bash
cd services/frontend
npm ci
npm run serve
```

📖 Подробнее — в [docs/devops/docker/readme.md](./docs/devops/docker/readme.md).

---

## ☁️ Деплой в Yandex Cloud

### Полный цикл — в четыре шага

```bash
# 1. Bootstrap (один раз на проект)
#    Создаёт S3-бакет для Terraform state, Container Registry, сервисный аккаунт
cd infrastructure/bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
# Сохранить: access_key, secret_key, registry_url

# 2. Настройка окружения
cd ../..
cp infrastructure/environments/staging/terraform.tfvars.example \
   infrastructure/environments/staging/terraform.tfvars
# Отредактировать terraform.tfvars

# 3. Деплой инфраструктуры
cd infrastructure
./scripts/apply.sh staging
# Делает: Terraform apply → ingress-nginx → monitoring → RBAC для CI

# 4. Деплой приложения
#    Push в main или ci/* → GitLab CI соберёт и задеплоит автоматически
git push origin main
```

### Проверка

```bash
cd infrastructure
./scripts/verify.sh
```

Скрипт проверяет: поды `Ready`, ресурсы мониторинга созданы, сайт открывается по `EXTERNAL-IP`, статика проксируется как JS, `/api/products` возвращает JSON.

### Релиз

```bash
git tag v1.2.3
git push origin v1.2.3
```

CI присвоит образам четыре Docker-тега (`1.2.3`, `1.2`, `1`, `latest`), загрузит статику в S3 и задеплоит в кластер. `helm upgrade --atomic` откатит релиз автоматически, если поды не станут `Ready`.

📖 Подробнее — в [docs/devops/infrastructure/readme.md](./docs/devops/infrastructure/readme.md).

---

## 📁 Структура репозитория

```
momo-store/
├── README.md                    # этот файл
├── docker-compose.yml           # локальный запуск
├── .gitlab-ci.yml               # основной пайплайн
│
├── ci/
│   └── diagnostics.yml          # диагностические джобы (запускаются вручную)
│
├── docs/
│   └── devops/
│       ├── ci-cd/               # пайплайн, переменные, диагностика
│       ├── docker/              # docker-compose, Dockerfile
│       ├── helm/                # описание чарта momo-store
│       ├── infrastructure/      # Terraform-модули, скрипты, RBAC
│       ├── observability/       # Prometheus + Grafana, дашборды, алерты
│       └── release-governance.md
│
├── infrastructure/
│   ├── bootstrap/               # создаётся 1 раз: S3 state, registry, SA
│   ├── environments/            # tfvars для staging/prod
│   ├── modules/
│   │   ├── networking/          # VPC, подсети, NAT, SG
│   │   ├── kubernetes-cluster/  # managed K8s
│   │   └── gitlab-runner/       # ВМ с GitLab Runner
│   ├── scripts/
│   │   ├── apply.sh             # Terraform + 3 post-apply скрипта
│   │   ├── setup-ingress-nginx.sh
│   │   ├── setup-monitoring.sh
│   │   ├── setup-ci-rbac.sh
│   │   └── verify.sh            # end-to-end проверка
│   ├── backend.tf
│   ├── main.tf
│   └── outputs.tf
│
├── k8s/
│   └── helm/
│       └── momo-store/          # Helm-чарт приложения
│           ├── Chart.yaml
│           ├── values.yaml
│           ├── values-staging.yaml
│           ├── values-prod.yaml
│           └── templates/
│               ├── backend/
│               ├── frontend/
│               ├── monitoring/
│               └── tests/
│
└── services/
    ├── backend/                 # Go API
    │   ├── cmd/api/
    │   ├── internal/
    │   ├── Dockerfile
    │   └── go.mod
    └── frontend/                # Vue.js + uploader
        ├── src/
        ├── public/
        ├── nginx/
        ├── Dockerfile
        └── package.json
```

---

## 🔄 Как проходит деплой

### Push в `main` или `ci/*`

1. **test** — `go vet`, `go test`, `npm run lint`, `helm lint`.
2. **build** — `docker build` + `docker push` с тегами `${CI_COMMIT_SHORT_SHA}`, `latest`.
3. **deploy** — `upload-static:staging` (S3) → `deploy:staging` (`helm upgrade --atomic`).

### Push git-тега `v1.2.3`

1. **test** — то же.
2. **build** — `docker build` + `docker push` с тегами `1.2.3`, `1.2`, `1`, `latest`.
3. **deploy** — загрузка статики → `helm upgrade --atomic` с `--set backend.image.tag=1.2.3`.

### Feature-ветки

Только стадия **test**. Никаких push и деплоя — безопасно.

📖 Подробнее — в [docs/devops/ci-cd/readme.md](./docs/devops/ci-cd/readme.md).

---

## 📊 Мониторинг и алерты

После деплоя:

- **Grafana:** `http://<EXTERNAL-IP>/monitoring` (login `admin`, пароль — `GRAFANA_ADMIN_PASSWORD`).
- **Prometheus:** скрейпит `/metrics` бэкенда через `ServiceMonitor`.
- **Дашборды:** три — Overview (RED), Business (заказы), Infrastructure (CPU/RAM/сеть).
- **Алерты:** четыре — CPU > 85%, disk > 85%, network RX/TX errors. Уходят на Gmail через contact point `gmail-alerts`.

Проверка:

```bash
# Поды мониторинга
kubectl get pods -n monitoring

# ServiceMonitor создан
kubectl get servicemonitor -n default

# ConfigMap с дашбордами
kubectl get configmap -n default momo-store-grafana-dashboards

# ConfigMap с алертами (в namespace monitoring!)
kubectl get configmap -n monitoring momo-store-grafana-alerting
```

📖 Подробнее — в [docs/devops/observability/readme.md](./docs/devops/observability/readme.md).

---

## 🔐 Переменные GitLab CI

Все секреты хранятся в **GitLab → Settings → CI/CD → Variables**. Кратко:

| Переменная | Назначение | Masked |
|---|---|---|
| `YC_SA_KEY_JSON` | Авторизация в `cr.yandex` (base64 от key.json) | ✅ |
| `AWS_ACCESS_KEY_ID` | Доступ к S3 | ✅ |
| `AWS_SECRET_ACCESS_KEY` | Доступ к S3 | ✅ |
| `S3_BUCKET` | Имя бакета со статикой | ❌ |
| `KUBE_CONFIG_STAGING` | Kubeconfig для деплоя (base64) | ✅ |
| `GRAFANA_SMTP_EMAIL` | Email для алертов Grafana | ❌ |

**Флаг `Protected` снят** со всех — иначе деплой из `ci/*` не получит переменные.

📖 Подробнее — в [docs/devops/ci-cd/variables.md](./docs/devops/ci-cd/variables.md).

---

## 🧪 Диагностика

Если что-то ломается — есть **отдельный набор диагностических джоб** в `ci/diagnostics.yml`. Они не подключены к основному пайплайну, запускаются вручную.

```bash
# Способ 1 — временная ветка
git checkout -b ci/run-diagnostics
mv .gitlab-ci.yml .gitlab-ci.main.yml
cp ci/diagnostics.yml .gitlab-ci.yml
git add . && git commit -m "ci: run diagnostics" && git push origin ci/run-diagnostics
```

Что проверяют `diag:*`:

| Джоба | Что |
|---|---|
| `diag:network` | Сеть до GitLab, `cr.yandex`, S3, registry.k8s.io, docker.io |
| `diag:dind` | Docker-in-docker |
| `diag:registry-login` | Авторизация в `cr.yandex` |
| `diag:s3` | Доступ к S3 |
| `diag:kubectl` | Доступ к кластеру |
| `diag:monitoring` | CRD `monitoring.coreos.com`, ConfigMap алертов, `GRAFANA_SMTP_EMAIL` |
| `diag:helm-lint` | Валидность чарта |
| `diag:helm-template` | Рендер с values |
| `diag:helm-test` | `helm test` — `/health` бэкенда, `/healthz` фронта |

📖 Подробнее — в [docs/devops/ci-cd/diagnostics.md](./docs/devops/ci-cd/diagnostics.md).

---

## 📚 Документация

### CI/CD

- [Пайплайн](./docs/devops/ci-cd/readme.md) — стадии, semver-релизы, `--atomic`, откат
- [Переменные](./docs/devops/ci-cd/variables.md) — `YC_SA_KEY_JSON`, `GRAFANA_SMTP_EMAIL`, RBAC
- [Диагностика](./docs/devops/ci-cd/diagnostics.md) — `diag:*`-джобы

### Helm-чарт

- [README чарта](./docs/devops/helm/readme.md) — быстрый старт, проверки, удаление
- [Архитектура](./docs/devops/helm/architecture.md) — компоненты, схема потоков, namespace'ы
- [Values reference](./docs/devops/helm/values-reference.md) — все ключи `values.yaml`
- [Deployment](./docs/devops/helm/deployment.md) — установка, troubleshooting

### Инфраструктура

- [Обзор](./docs/devops/infrastructure/readme.md) — модули, скрипты, RBAC, `verify.sh`
- [Bootstrap](./docs/devops/infrastructure/bootstrap.md) — S3 state, Container Registry, SA
- [Networking](./docs/devops/infrastructure/networking.md) — VPC, подсети, NAT, SG
- [Kubernetes Cluster](./docs/devops/infrastructure/kubernetes-cluster.md) — managed K8s
- [GitLab Runner](./docs/devops/infrastructure/gitlab-runner.md) — установка раннера

### Observability

- [Обзор](./docs/devops/observability/readme.md) — Prometheus + Grafana, доступ, переменные
- [Дашборды](./docs/devops/observability/dashboards.md) — три дашборда, метрики
- [Алерты](./docs/devops/observability/alerts.md) — четыре алерта, contact point, SMTP

### Docker

- [Docker](./docs/devops/docker/readme.md) — docker-compose, Dockerfile

---

## 🔒 Безопасность

- **Секреты — только в переменных окружения** (`YC_*`, `AWS_*`, `TF_VAR_*`, `GITLAB_*`, `GRAFANA_*`). Никогда не коммитить `terraform.tfvars`, `key.json`, `outputs.json`, `*.tfstate`.
- **RBAC разделён:** `ingress-nginx` и `monitoring` ставятся админом (cluster-wide), CI имеет namespace-scoped доступ (`default` + `monitoring`).
- **Terraform state — в S3** с версионированием и lifecycle (удаление старых версий через 30 дней).
- **Gmail App Password** — не основной пароль аккаунта. Хранится в Kubernetes Secret `grafana-smtp-secret`.

---

## 📦 Стек

| Слой | Технологии |
|---|---|
| Backend | Go 1.21+, Prometheus client |
| Frontend | Vue.js 3, TypeScript, Webpack |
| Reverse proxy | nginx 1.27-alpine |
| Контейнеризация | Docker, Docker Compose, BuildKit |
| Оркестрация | Kubernetes (Yandex Managed Service for Kubernetes) |
| IaC | Terraform ≥ 1.5 |
| CI/CD | GitLab CI, Docker-in-docker |
| Пакетный менеджер | Helm 3 |
| Мониторинг | Prometheus, Grafana, node-exporter, kube-state-metrics |
| Облако | Yandex Cloud (VPC, K8s, S3, Container Registry, NLB) |

---

## 📄 Лицензия

Учебный проект. Используется в рамках курса по DevOps.