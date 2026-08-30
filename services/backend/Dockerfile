# ============================================
# service/backcend/Dockerfile
# ============================================

# ============ ЭТАП 1: Зависимости ============
FROM golang:1.23.0-alpine3.20 AS deps

WORKDIR /app

# Копируем go.mod и go.sum
COPY go.mod go.sum ./
RUN go mod download

# ============ ЭТАП 2: Сборка ============
FROM deps AS builder

# Аргументы для сборки
ARG BACKEND_VERSION

# Копируем код
COPY . .

# Собираем бинарник
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s -X main.version=${BACKEND_VERSION:-1.1.0}" \
    -o api \
    ./cmd/api

# ============ ЭТАП 3: Финальный образ ============
FROM alpine:3.20

ARG BACKEND_PORT=8081

# Устанавливаем пакеты и создаем пользователя в одном RUN
RUN apk --no-cache add ca-certificates curl wget && \
    addgroup -g 1000 -S appgroup && \
    adduser -u 1000 -S appuser -G appgroup

WORKDIR /app

# Копируем бинарник
COPY --from=builder /app/api .

# Меняем владельца
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE ${BACKEND_PORT}

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8081/health || exit 1

CMD ["./api"]