# Архитектура чарта momo-store

## Компоненты

### Backend
- **Образ**: cr.yandex/.../momo-store-backend
- **Порт**: 8081
- **Health**: /health
- **API**: /products, /categories

### Frontend
- **Образ**: nginx:1.27-alpine
- **Порт**: 80
- **Назначение**: проксирование статики из S3 + SPA-роутинг
- **Конфиг**: ConfigMap momo-store-frontend-nginx

### Ingress
- **Тип**: ingress-nginx
- **Пути**:
  - `/api` → backend:8081 (с rewrite-target)
  - `/` → frontend:80

### LoadBalancer
- **Тип**: Yandex Cloud NLB (EXTERNAL)
- **Порты**: 80, 443
- **SG**: yandex.cloud/security-group-ids

## Схема потоков

[диаграмма: браузер → LB → ingress → frontend/backend → S3]

## Особенности

### S3-статика
- Все статические файлы (js, css, img) лежат в Object Storage.
- Frontend-Nginx проксирует их через proxy_pass в S3.
- Префикс `momo-store/` уже в URI от браузера, поэтому `$s3_prefix` НЕ добавляется.
- Для `location = /` используется `$s3_prefix/index.html` — потому что браузер просит `/`.

### DNS-резолвинг
- Nginx использует `resolver <ClusterIP kube-dns>` для runtime-резолвинга `storage.yandexcloud.net`.
- ClusterIP kube-dns меняется при пересоздании кластера.

### rewrite-target
- Аннотация `nginx.ingress.kubernetes.io/rewrite-target: /$2` применяется только к ingress `momo-store-api`.
- Для frontend используется отдельный ingress без rewrite.