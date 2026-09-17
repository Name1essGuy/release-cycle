# ============================================
# services/frontend/Dockerfile
# ============================================

# ============ ЭТАП 1: Prod зависимости ============
FROM node:18.20.4-alpine3.20 AS deps

WORKDIR /app

COPY package*.json ./

RUN npm ci --only=production && \
    npm cache clean --force

# ============ ЭТАП 2: Dev-зависимости для сборки ============
FROM deps AS dev-deps

RUN npm install --only=development

# ============ ЭТАП 3: Сборка статики (PROD) ============
FROM dev-deps AS builder

ARG VUE_APP_API_URL
ARG VUE_APP_VERSION
ARG NODE_ENV=production

ENV VUE_APP_API_URL=${VUE_APP_API_URL:-/api}
ENV VUE_APP_VERSION=${VUE_APP_VERSION:-1.0.0}
ENV NODE_ENV=${NODE_ENV}

COPY . .

RUN npm run build

# ============ ЭТАП 4: Загрузка статики в S3 (PROD) ============
FROM alpine:3.20 AS uploader

RUN apk add --no-cache aws-cli

ENV S3_BUCKET=""
ENV S3_ENDPOINT="https://storage.yandexcloud.net"
ENV S3_PREFIX="momo-store"

COPY --from=builder /app/dist /static

WORKDIR /static

# Загружаем ВСЁ (включая index.html) в папку momo-store/
CMD aws --endpoint-url=${S3_ENDPOINT} s3 sync /static/ s3://${S3_BUCKET}/${S3_PREFIX}/ --delete && \
    echo "✅ Static files uploaded to s3://${S3_BUCKET}/${S3_PREFIX}/"

# ============ ЭТАП 5: Dev-режим (локальная разработка) ============
FROM dev-deps AS development

ARG BACKEND_PORT=8081

ENV NODE_ENV=development
ENV VUE_APP_API_URL=http://localhost:${BACKEND_PORT}/api

COPY . .

EXPOSE 8080

CMD ["sh", "-c", "npm run serve -- --host 0.0.0.0 --port 8080"]

# ============ ЦЕЛЬ ПО УМОЛЧАНИЮ: PROD ============
FROM uploader