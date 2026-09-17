# Docker конфигурация проекта

## Обзор
Проект состоит из двух сервисов:

| Сервис | Технология | Порт | Режимы |
| :--- | :--- | :--- | :--- |
| **backend** | Go API | 8081 | `development`, `production` |
| **frontend** | Vue.js | 8080 (dev) / S3 (prod) | `development`, `uploader` |

**Ключевое отличие:** фронтенд в production **не разворачивается в контейнере**, а собирается и загружается в **S3-бакет** для раздачи статики.

## Структура Docker файлов
```
.
├── docker-compose.yml # Основной compose файл
├── services/
│ ├── backend/
│ │ └── Dockerfile # Сборка Go приложения
│ └── frontend/
│ ├── Dockerfile # Сборка Vue приложения
│ └── nginx.conf # Конфигурация Nginx для продакшена
└── .env.example # Пример переменных окружения
```


---

## Режимы сборки

### 🛠️ Development (локальная разработка)

Запускается **локальный dev-сервер** с горячей перезагрузкой:

- **Backend**: `go run ./cmd/api` (или `air` для hot-reload)
- **Frontend**: `npm run serve` на порту `8080`

### 🚀 Production (развёртывание)

- **Backend**: собирается бинарник, упаковывается в Alpine-образ
- **Frontend**: собирается статика (`npm run build`) и **загружается в S3** через `aws s3 sync`

---

## Docker Compose

### Основные команды

#### Dev-режим (локальная разработка)

```bash
# Запустить все сервисы в dev-режиме
docker compose --profile dev up -d --build

# Только frontend-dev
docker compose --profile dev up frontend-dev
```

Доступ:

- Frontend: http://localhost:8080
- Backend: http://localhost:8081

### Prod-режим (сборка + загрузка в S3)


``` bash
# Собрать backend
docker compose build backend

# Собрать и загрузить статику в S3
docker compose --profile deploy build frontend-uploader
docker compose --profile deploy up frontend-uploader
```
Остановка:

``` bash
docker compose --profile dev down
```

Просмотр логов:

``` bash
# Все сервисы
docker compose logs -f

# Конкретный сервис
docker compose logs -f backend
docker compose logs -f frontend-dev
```

Проверка статуса:
``` bash
docker compose ps
```

## Переменные окружения

Создайте `.env` на основе `.env.example`

``` bash
cp .env.example .env
```


| Переменная | Описание | По умолчанию | Особенности |
|------------|----------|--------------|-------------|
| `BACKEND_PORT` | Порт бэкенда | `8081` | Из доступного диапазона |
| `BACKEND_VERSION` | Версия бэкенда | `1.0.0` | Передаётся в бинарник через `ldflags` |
| `NODE_ENV` | Среда | `production` | `development` или `production` |
| `FRONTEND_PORT` | Порт dev-сервера фронтенда | `8080` | Только для dev |
| `VUE_APP_API_URL` | URL API для фронтенда | `/api` | Для prod — относительный путь |
| `VUE_APP_VERSION` | Версия фронтенда | `1.0.0` | — |
| `S3_BUCKET` | Имя S3-бакета для статики | `momo-store-frontend` | Только для prod |
| `S3_ENDPOINT` | Endpoint Object Storage | `https://storage.yandexcloud.net` | — |
| `S3_PREFIX` | Папка в бакете | `momo-store` | — |
| `AWS_ACCESS_KEY_ID` | Ключ доступа к S3 | — | Из bootstrap |
| `AWS_SECRET_ACCESS_KEY` | Секретный ключ S3 | — | Из bootstrap |

---

## Сборка образов

### Локальная сборка

``` bash
# Все сервисы (prod)
docker compose build

# Только backend
docker compose build backend

# Frontend-uploader (prod)
docker compose --profile deploy build frontend-uploader

# Frontend-dev (dev)
docker compose --profile dev build frontend-dev
```

### Сборка с тэгами для реестра

```bash
REGISTRY=cr.yandex/crpcti5ji1nf9q4ofu6j

# Backend
docker build -t $REGISTRY/momo-store-backend:1.1.0 ./services/backend
docker build -t $REGISTRY/momo-store-backend:latest ./services/backend

# Frontend-uploader
docker build --target uploader \
  --build-arg VUE_APP_API_URL=/api \
  --build-arg VUE_APP_VERSION=1.1.0 \
  -t $REGISTRY/momo-store-frontend-uploader:1.1.0 \
  ./services/frontend
```

### Публикация в реестр

``` bash
REGISTRY=cr.yandex/crpcti5ji1nf9q4ofu6j

# Backend
docker build -t $REGISTRY/momo-store-backend:1.1.0 ./services/backend
docker build -t $REGISTRY/momo-store-backend:latest ./services/backend

# Frontend-uploader
docker build --target uploader \
  --build-arg VUE_APP_API_URL=/api \
  --build-arg VUE_APP_VERSION=1.1.0 \
  -t $REGISTRY/momo-store-frontend-uploader:1.1.0 \
  ./services/frontend
```

---

## Загрузка статики в S3

После сборки `frontend-uploader` запустите его для загрузки статики:

```bash
docker run --rm \
  -e S3_BUCKET=momo-store-frontend \
  -e S3_ENDPOINT=https://storage.yandexcloud.net \
  -e S3_PREFIX=momo-store \
  -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  $REGISTRY/momo-store-frontend-uploader:1.1.0
```

**Результат**: статика окажется в s3://momo-store-frontend/momo-store/.

---

## Особенности сборки

### Development

При `NODE_ENV=development`:

- Frontend: запускается dev-сервер npm run serve на порту 8080
- Backend: запускается go run (или air для hot-reload)

### Production

При `NODE_ENV=production`:

- Frontend: собирается оптимизированная статика и загружается в S3
- Backend: собирается бинарник, упаковывается в минимальный Alpine-образ

---

## Сети

```yaml
networks:
  momo-network:
    driver: bridge
    name: momo-network
```

---

## Итоговая схема

```
┌─────────────────────────────────────────────────────────────┐
│  DEV                                                        │
│  ┌──────────────┐         ┌──────────────┐                  │
│  │  frontend    │ ──────► │  backend     │                  │
│  │  :8080       │         │  :8081       │                  │
│  └──────────────┘         └──────────────┘                  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  PROD                                                       │
│  ┌──────────────┐         ┌──────────────┐                  │
│  │  S3 Bucket   │         │  backend     │                  │
│  │  (статика)   │         │  (K8s)       │                  │
│  └──────────────┘         └──────────────┘                  │
│         ▲                        ▲                          │
│         │                        │                          │
│         └────────┬───────────────┘                          │
│                  │                                          │
│            ┌──────────┐                                     │
│            │ Ingress  │                                     │
│            └──────────┘                                     │
└─────────────────────────────────────────────────────────────┘
```