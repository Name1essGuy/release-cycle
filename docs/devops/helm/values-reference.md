# Справочник по values.yaml

## global

| Параметр | Тип | Описание | По умолчанию |
|---|---|---|---|
| `imagePullSecrets` | list | Секреты для pull образов | `[ycr-secret]` |

> **`imagePullSecrets`** применяется и к backend, и к frontend. Секрет должен существовать в том же namespace, куда ставится чарт (`default`). Создать: `kubectl create secret docker-registry ycr-secret ...` — см. [deployment.md](./deployment.md#3-секрет-ycr-secret).

---

## backend

| Параметр | Тип | Описание | По умолчанию |
|---|---|---|---|
| `enabled` | bool | Включить backend | `true` |
| `replicaCount` | int | Количество реплик | `1` |
| `image.repository` | string | Образ | `cr.yandex/.../momo-store-backend` |
| `image.tag` | string | Тег | `latest` |
| `image.pullPolicy` | string | Политика pull | `IfNotPresent` |
| `service.type` | string | Тип Service | `ClusterIP` |
| `service.port` | int | Порт сервиса | `8081` |
| `service.targetPort` | int | Порт пода | `8081` |
| `resources.*` | object | Лимиты CPU/памяти | см. values.yaml |
| `env` | list | Переменные окружения | `[NODE_ENV=production]` |
| `probes.liveness.*` | object | Liveness probe | `/health`, 10s |
| `probes.readiness.*` | object | Readiness probe | `/health`, 5s |

> **`image.tag: latest` — только для локального деплоя.** В CI тег всегда передаётся явно:
> - на push в `main`/`ci/*` — `${CI_COMMIT_SHORT_SHA}`;
> - на git-тег — semver (`1.2.3`).
>
> См. [CI/CD: semver-релизы](../ci-cd/readme.md#-semver-релизы).

### Probes

```yaml
backend:
  probes:
    liveness:
      path: /health
      port: 8081
      initialDelaySeconds: 10
      periodSeconds: 10
    readiness:
      path: /health
      port: 8081
      initialDelaySeconds: 5
      periodSeconds: 5
```

- `/health` — эндпоинт Go-API, отвечает `200 OK`, когда сервис готов.
- Если `liveness` падает — kubelet перезапускает контейнер.
- Если `readiness` падает — под убирается из Service endpoints.

---

## frontend

| Параметр | Тип | Описание | По умолчанию |
|---|---|---|---|
| `enabled` | bool | Включить frontend | `true` |
| `replicaCount` | int | Количество реплик | `1` |
| `image.repository` | string | Образ | `nginx` |
| `image.tag` | string | Тег | `1.27-alpine` |
| `image.pullPolicy` | string | Политика pull | `IfNotPresent` |
| `s3.endpoint` | string | S3 endpoint | `storage.yandexcloud.net` |
| `s3.bucket` | string | Имя бакета | `momo-store-frontend` |
| `s3.prefix` | string | Префикс внутри бакета | `momo-store` |
| `dnsResolver` | string | ClusterIP kube-dns для nginx resolver | `10.96.128.2` |
| `service.type` | string | Тип Service | `ClusterIP` |
| `service.port` | int | Порт сервиса | `80` |
| `service.targetPort` | int | Порт пода | `80` |
| `resources.*` | object | Лимиты CPU/памяти | см. values.yaml |
| `probes.liveness.*` | object | Liveness probe | `/healthz`, 10s |
| `probes.readiness.*` | object | Readiness probe | `/healthz`, 5s |

> **`dnsResolver`** — ClusterIP `kube-dns` в текущем кластере. Меняется при пересоздании кластера. Получить:
> ```bash
> kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}'
> ```

### Probes

```yaml
frontend:
  probes:
    liveness:
      path: /healthz
      port: 80
      initialDelaySeconds: 10
      periodSeconds: 10
    readiness:
      path: /healthz
      port: 80
      initialDelaySeconds: 5
      periodSeconds: 5
```

- `/healthz` — статический `return 200 "ok\n"` в nginx. **Не ходит в S3** — чтобы недоступность Object Storage не роняла поды.
- Реализован в `templates/frontend/nginx-configmap.yaml`.

---

## ingress

| Параметр | Тип | Описание | По умолчанию |
|---|---|---|---|
| `enabled` | bool | Включить Ingress | `true` |
| `className` | string | IngressClass | `nginx` |
| `hosts` | list | Список хостов и путей | см. values.yaml |
| `hosts[].paths[].path` | string | Путь | `/api`, `/` |
| `hosts[].paths[].service` | string | Имя сервиса (backend или frontend) | — |
| `hosts[].paths[].port` | int | Порт сервиса | `8081`, `80` |

> **`className: nginx`** требует установленного `ingress-nginx`. Если его нет — Ingress создастся, но трафик никуда не пойдёт. Установка: `setup-ingress-nginx.sh staging`.

> **`rewrite-target`** — аннотация применяется **только** к Ingress `momo-store-api`. Для frontend — отдельный Ingress без rewrite. См. [architecture.md → rewrite-target](./architecture.md#rewrite-target).

---

## monitoring

| Параметр | Тип | Описание | По умолчанию |
|---|---|---|---|
| `monitoring.enabled` | bool | Включить создание ресурсов мониторинга | `true` |
| `monitoring.releaseLabel` | string | Метка `release`, по которой Prometheus находит ServiceMonitor | `monitoring` |
| `monitoring.serviceMonitor.enabled` | bool | Создавать ServiceMonitor | `true` |
| `monitoring.dashboard.enabled` | bool | Создавать ConfigMap с дашбордами Grafana | `true` |
| `monitoring.alerting.enabled` | bool | Создавать ConfigMap с алертами Grafana | `true` |
| `monitoring.alerting.email` | string | **Обязательно при `alerting.enabled=true`.** Email для contact point `gmail-alerts` | — |
| `monitoring.prometheusRule.enabled` | bool | Создавать PrometheusRule (legacy, только для UI Grafana) | `true` |

> **`monitoring.alerting.email`** не имеет значения по умолчанию. Если `monitoring.alerting.enabled=true` и email не задан — `helm upgrade` упадёт с ошибкой:
> ```
> monitoring.alerting.email is required when monitoring.alerting.enabled=true
> ```
> Передаётся при деплое:
> ```bash
> helm upgrade -i momo-store ./ \
>   -f values.yaml -f values-staging.yaml \
>   --set monitoring.alerting.email="${GRAFANA_SMTP_EMAIL}"
> ```

> **`monitoring.releaseLabel`** должен совпадать с именем Helm-релиза `kube-prometheus-stack`. У нас он установлен как `monitoring` — значит метка тоже `monitoring`. Если переустановите Prometheus с другим именем релиза — обновите эту переменную.

> **Namespace'ы ресурсов мониторинга:**
>
> | Ресурс | Namespace | Почему |
> |---|---|---|
> | `ServiceMonitor/momo-store-backend` | `default` (namespace релиза) | Prometheus ищет ServiceMonitor во всех namespace |
> | `ConfigMap/momo-store-grafana-dashboards` | `default` | sidecar Grafana с `searchNamespace=ALL` |
> | `ConfigMap/momo-store-grafana-alerting` | `monitoring` | alerts-sidecar смотрит только в свой namespace |
> | `PrometheusRule/momo-store-alerts` | `default` | CRD namespace-scoped, для UI Grafana |
>
> Если `ci-deployer` деплоит чарт из CI — у него должны быть права на `configmaps` в namespace `monitoring`. См. [CI/CD: переменные](../ci-cd/variables.md#-kube_config_staging).

---

## Что **не** входит в values

Раньше в чарте был блок `ingress-nginx` — как зависимость. Сейчас `ingress-nginx` **вынесен** из чарта и устанавливается отдельно через `setup-ingress-nginx.sh`. Все его параметры (включая SG для LB) теперь задаются **там**, а не в `values.yaml` чарта `momo-store`.

Аналогично — `kube-prometheus-stack` устанавливается **отдельно** через `setup-monitoring.sh`. Чарт `momo-store` только создаёт ресурсы, которые этот стек подхватывает.

---

## Особенности окружений

### `values.yaml` (базовый)

Дефолты для локального деплоя:

- `dnsResolver: 10.96.128.2`
- `monitoring.alerting.email` — **пусто**, задаётся при деплое через `--set`
- `backend.image.tag: latest` — в CI перезаписывается

### `values-staging.yaml`

| Параметр | Значение |
|---|---|
| `backend.replicaCount` | 1 |
| `backend.image.tag` | `1.1.0` |
| `frontend.replicaCount` | 1 |
| `frontend.s3.bucket` | `momo-store-frontend` |
| `monitoring.alerting.email` | задаётся через `--set` |

### `values-prod.yaml`

| Параметр | Значение |
|---|---|
| `backend.replicaCount` | 3 |
| `backend.image.tag` | `1.1.0` |
| `backend.image.pullPolicy` | `Always` |
| `frontend.replicaCount` | 3 |
| `frontend.s3.bucket` | `momo-store-frontend` |
| `monitoring.alerting.email` | задаётся через `--set` |

> **В `values-staging.yaml` и `values-prod.yaml` блок `monitoring` не переопределяется.** Иначе Helm сделает shallow-merge и потеряет вложенные ключи (`serviceMonitor`, `dashboard`, `alerting`) — они обнулятся, и ресурсы мониторинга не создадутся. Если нужно поменять что-то в `monitoring` для конкретного окружения — переопределяйте **весь блок** целиком, а не отдельный ключ.

---

## Связанные документы

- [README чарта](./readme.md) — быстрый старт, проверки, удаление
- [Архитектура](./architecture.md) — компоненты, схема потоков, namespace'ы
- [Deployment](./deployment.md) — установка, troubleshooting
- [CI/CD: переменные](../ci-cd/variables.md) — `GRAFANA_SMTP_EMAIL`, RBAC на `monitoring`
- [Observability](../observability/readme.md) — дашборды, алерты