# ============================================
# services/frontend/Dockerfile
# ============================================

# ============ ЭТАП 1: Prod зависимости ============
FROM node:18.20.4-alpine3.20 AS deps

WORKDIR /app

# Копируем package.json и package-lock.json
COPY package*.json ./

# Устанавливаем production зависимости
RUN npm ci --only=production && \
    npm cache clean --force

# ============ ЭТАП 2: Dev-зависимости для сборки ============
FROM deps AS dev-deps

# Добавляем dev-зависимости поверх production
RUN npm install --only=development

# ============ ЭТАП 3: Сборка для продакшена============
FROM dev-deps AS builder

# Аргументы для сборки
ARG VUE_APP_API_URL
ARG VUE_APP_VERSION
ARG NODE_ENV=production

# Передаем переменные окружения
ENV VUE_APP_API_URL=${VUE_APP_API_URL:-/api/}
ENV VUE_APP_VERSION=${VUE_APP_VERSION:-1.0.0}
ENV NODE_ENV=${NODE_ENV}

COPY . .

# Собираем приложение
RUN npm run build


# ============ ЭТАП 3: Режим разработки (npm run serve) ============
FROM deps AS development

# Аргументы для разработки
ARG BACKEND_PORT=8081

# Переменные окружения для dev
ENV NODE_ENV=development
ENV VUE_APP_API_URL=http://backend:${BACKEND_PORT}

# Копируем исходники
COPY . .

# Открываем порт для dev сервера
EXPOSE 8080

# Запускаем dev сервер
CMD ["sh", "-c", "npm run serve -- --host 0.0.0.0 --port 8080"]

# ============ ЭТАП 4: Продакшен с Nginx ============
FROM nginx:1.26.2-alpine3.20 AS production

ARG FRONTEND_PORT=80
ARG BACKEND_PORT=8081

ENV FRONTEND_PORT=${FRONTEND_PORT}
ENV BACKEND_PORT=${BACKEND_PORT}

# Устанавливаем утилиты и создаем пользователя
RUN apk --no-cache add curl gettext && \
    addgroup -g 1000 -S appgroup && \
    adduser -u 1000 -S appuser -G appgroup && \
    mkdir -p /app/run && \
    mkdir -p /app/logs && \
    mkdir -p /var/lib/nginx/tmp && \
    chown -R appuser:appgroup /app && \
    chown -R appuser:appgroup /var/lib/nginx && \
    chown -R appuser:appgroup /var/log/nginx && \
    chown -R appuser:appgroup /var/cache/nginx

# Копируем собранные файлы
COPY --from=builder /app/dist /usr/share/nginx/html

# Копируем шаблон для виртуальных хостов
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template

# Копируем основной конфиг
COPY nginx/nginx.conf /etc/nginx/nginx.conf

# Явно подставляем переменные в шаблон nginx
RUN envsubst '${FRONTEND_PORT} ${BACKEND_PORT}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf

USER appuser

EXPOSE ${FRONTEND_PORT}

# Проверка живости
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:${FRONTEND_PORT}/health || exit 1

CMD ["nginx", "-g", "daemon off;"]

# ============ ЦЕЛЬ ПО УМОЛЧАНИЮ ============
FROM production