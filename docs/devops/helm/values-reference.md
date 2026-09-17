# Справочник по values.yaml

## global

| Параметр | Тип | Описание | По умолчанию |
|---|---|---|---|
| `imagePullSecrets` | list | Секреты для pull образов | `[ycr-secret]` |

## backend

| Параметр | Тип | Описание | По умолчанию |
|---|---|---|---|
| `enabled` | bool | Включить backend | `true` |
| `replicaCount` | int | Количество реплик | `1` |
| `image.repository` | string | Образ | `cr.yandex/.../momo-store-backend` |
| `image.tag` | string | Тег | `latest` |
| `service.port` | int | Порт сервиса | `8081` |
| `env` | list | Переменные окружения | `[NODE_ENV=production]` |
| `probes.*` | object | Liveness/readiness | ... |

## frontend

| Параметр | Тип | Описание | По умолчанию |
|---|---|---|---|
| `enabled` | bool | Включить frontend | `true` |
| `replicaCount` | int | Количество реплик | `1` |
| `image.repository` | string | Образ | `nginx` |
| `image.tag` | string | Тег | `1.27-alpine` |
| `s3.endpoint` | string | S3 endpoint | `storage.yandexcloud.net` |
| `s3.bucket` | string | Имя бакета | `momo-store-frontend` |
| `s3.prefix` | string | Префикс в бакете | `momo-store` |
| `dnsResolver` | string | ClusterIP kube-dns для nginx resolver | `10.96.128.2` |

## ingress

| Параметр | Описание |
|---|---|
| `enabled` | Включить ingress |
| `className` | IngressClass | `nginx` |
| `hosts` | Список host'ов и путей |

## ingress-nginx

| Параметр | Описание |
|---|---|
| `enabled` | Установить ingress-nginx как dependency |
| `controller.service.annotations` | Аннотации LB, включая SG |

## Особенности окружений

### values-staging.yaml
- replicaCount: 1
- SG: `enp9j57sm9p4obvnaure`
- dnsResolver: актуальный ClusterIP kube-dns

### values-prod.yaml
- replicaCount: 3
- SG: prod-SG
- dnsResolver: актуальный ClusterIP kube-dns