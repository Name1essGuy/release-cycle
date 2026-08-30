# Docker конфигурация проекта

## Обзор
Проект состоит из двух сервисов, каждый из которых упакован в отдельный Docker образ:
- **backend** - Go API сервис (порт 8081)
- **frontend** - Vue.js приложение (порт 80)

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

## Docker Compose

### Основные команды

#### Запуск всех сервисов
```bash
docker-compose up -d
```

#### Остановка всех сервисов
```bash
docker-compose down
```

#### Пересборка и запуск
```bash
docker-compose up -d --build
```

#### Просмотр логов
```bash
# Все сервисы
docker-compose logs -f

# Конкретный сервис
docker-compose logs -f backend
docker-compose logs -f frontend
```

#### Проверка статуса
```bash
docker-compose ps
```

### Переменные окружения
Переименуйте файл `.env.example` в корне проекта в `.env` и отредактируйте нужные переменные.

Описание переменных:
| Переменная | Описание | Значение по умолчанию | Особенности |
|-----------|-----------|------------------------|-------------|
| BACKEND_PORT | Порт, на котором будет работать бэкэнд | 8081 | Значением должен быть порт из доступного диапазона |
| BACKEND_VERSION | Версия бэкэнда | 1.0.0 | |
| NODE_ENV | Среда деплоя | production | Может быть только `development` или `production` |
| FRONTEND_PORT | Порт, на котором будет работать фронтэнд | 80 | Значением должен быть порт из доступного диапазона |


## Сборка образов
### Локальная сборка

```bash
docker-compose build
```
Для сборки на `development` среду установите переменную `NODE_ENV=development`

### Сборка с тегами для реестра
```bash
# Backend
docker build -t registry.example.com/backend:latest ./services/backend
docker build -t registry.example.com/backend:1.0.0 ./services/backend

# Frontend
docker build -t registry.example.com/frontend:latest ./services/frontend
docker build -t registry.example.com/frontend:1.0.0 ./services/frontend
```

### Публикация в реестр

```bash
docker push registry.example.com/backend:latest
docker push registry.example.com/frontend:latest
```

## Сети

```bash
networks:
  app-network:
    driver: bridge
```

## Особенности сборки

### Development сборка

При установке переменной окружения `NODE_ENV=development` собирается dev-версия сервиса. Её ключевая особенность - **локальный запуск с помощью сервера разработки**, который не требует предварительной сборки статики.

### Production сборка

При установке переменной окружения `NODE_ENV=production` собирается prod-версия сервиса. Её ключевая особенность - **создание оптимизированных статических файлов**, развёртываемых на веб-сервере Nginx.