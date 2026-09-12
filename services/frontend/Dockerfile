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

# ============ ЭТАП 3: Сборка статики ============
FROM dev-deps AS builder

ARG VUE_APP_API_URL
ARG VUE_APP_VERSION
ARG NODE_ENV=production

ENV VUE_APP_API_URL=${VUE_APP_API_URL:-/api/}
ENV VUE_APP_VERSION=${VUE_APP_VERSION:-1.0.0}
ENV NODE_ENV=${NODE_ENV}

COPY . .

RUN npm run build

# ============ ЭТАП 4: Загрузка статики в S3 ============
# ============ ЭТАП 4: Загрузка статики в S3 ============
FROM alpine:3.20 AS uploader

RUN apk add --no-cache aws-cli

ENV S3_BUCKET=""
ENV S3_ENDPOINT="https://storage.yandexcloud.net"
ENV S3_PREFIX="momo-store"

COPY --from=builder /app/dist /static

WORKDIR /static

# 1. Загружаем index.html в корень бакета
# 2. Загружаем остальную статику в подпапку momo-store/
CMD aws --endpoint-url=${S3_ENDPOINT} s3 cp /static/index.html s3://${S3_BUCKET}/index.html && \
    aws --endpoint-url=${S3_ENDPOINT} s3 sync /static/ s3://${S3_BUCKET}/${S3_PREFIX}/ --exclude "index.html" --delete && \
    echo "✅ Static files uploaded to s3://${S3_BUCKET}/"

# ============ ЦЕЛЬ ПО УМОЛЧАНИЮ ============
FROM uploader