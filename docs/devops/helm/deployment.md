# Деплой и обновление

## Предварительная проверка

### 1. ClusterIP kube-dns

```bash
kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}'
```

Впишите в `values-<env>.yaml` → `frontend.dnsResolver`.

### 2. ID Security Group для LB

```bash
yc vpc security-group get --name <env>-sg-ingress-lb --format json | jq -r '.id'
```

Впишите в `values-<env>.yaml` → `ingress-nginx.controller.service.annotations."yandex.cloud/security-group-ids"` (если ingress-nginx ставится через values, иначе — в `setup-ingress-nginx.sh`).

### 3. Секрет ycr-secret

```bash
kubectl get secret ycr-secret -n default
```

Если нет — создайте:

```bash
kubectl create secret docker-registry ycr-secret \
  --docker-server=cr.yandex \
  --docker-username=json_key \
  --docker-password="$(cat key.json)"
```

### 4. Переменная GRAFANA_SMTP_EMAIL

```bash
echo "$GRAFANA_SMTP_EMAIL"
```

Должна быть задана — иначе `helm upgrade` упадёт при `monitoring.enabled=true`.

### 5. Что установлены ingress-nginx и monitoring

```bash
# ingress-nginx
helm list -n ingress-nginx
kubectl get svc -n ingress-nginx ingress-nginx-controller

# monitoring
helm list -n monitoring
kubectl get pods -n monitoring
```

Оба — устанавливаются **отдельно** от чарта `momo-store`:

- `setup-ingress-nginx.sh staging`
- `setup-monitoring.sh staging`

### 6. RBAC для CI (если деплой из пайплайна)

Если чарт ставится из GitLab CI, у `ci-deployer` должны быть права на:

- namespace `default` — для Deployment, Service, Ingress, ServiceMonitor, PrometheusRule;
- namespace `monitoring` — для `ConfigMap/momo-store-grafana-alerting`.

Проверка:

```bash
kubectl get role,rolebinding -n default | grep ci-deployer
kubectl get role,rolebinding -n monitoring | grep ci-deployer
```

Если второй команды ничего не вернула — см. [Troubleshooting](#-troubleshooting) ниже.

---

## Установка и обновление

```bash
helm upgrade -i momo-store ./ \
  -f values.yaml \
  -f values-<env>.yaml \
  --set monitoring.alerting.email="${GRAFANA_SMTP_EMAIL}" \
  --namespace default \
  --atomic \
  --wait --timeout 5m
```

**Ключевые флаги:**

- `--set monitoring.alerting.email` — обязателен при `monitoring.alerting.enabled=true`.
- `--atomic` — автоматический откат при провале деплоя (см. ниже).
- `--wait --timeout 5m` — дождаться готовности подов.
- `--namespace default` — чарт ставится в `default` (там же, где `ci-deployer` имеет права).

### Про `--atomic`

Если поды не станут `Ready` за 5 минут (probes не прошли, под в `CrashLoopBackOff`, образ не скачался), Helm автоматически откатит релиз к предыдущей успешной ревизии.

```
Error: UPGRADE FAILED: release momo-store failed, and has been rolled back due to atomic being set:
Error: context deadline exceeded
```

История:

```bash
helm history momo-store -n default
```

```
REVISION  STATUS      DESCRIPTION
1         superseded  Install complete
2         failed      Upgrade "momo-store" failed: context deadline exceeded
3         deployed    Rollback to 1
```

**Ограничение:** `--atomic` не ловит логические ошибки. Если под стартанул и отвечает на probes, но `/api/products` возвращает 500 — Helm считает релиз успешным. Для проверки бизнес-логики — `helm test` и `verify.sh` (см. [«Проверка после деплоя»](#-проверка-после-деплоя)).

Подробнее про `--atomic` — в [CI/CD: автоматический откат](../ci-cd/readme.md#-автоматический-откат-при-провале-деплоя).

---

## Проверка после деплоя

### 1. Поды

```bash
kubectl get pods -n default
```

Ожидаемо: `momo-store-backend-*` и `momo-store-frontend-*` в статусе `Running`.

### 2. `helm test`

Чарт содержит тестовые поды. Запустить:

```bash
helm test momo-store -n default --logs
```

Проверяет:

| Test | Что |
|---|---|
| `test-backend` | `GET /health` на сервисе backend → 200 |
| `test-frontend` | `GET /healthz` → 200 и `GET /momo-store/js/...` → `Content-Type: application/javascript` |

Если `test-frontend` упал с `Content-Type: text/html` — nginx отдаёт `index.html` вместо JS. Смотрите `templates/frontend/nginx-configmap.yaml` и `dnsResolver` в `values.yaml`.

> **`helm test` не запускается автоматически** в пайплайне. В CI есть джоба `diag:helm-test` (в `ci/diagnostics.yml`), но она запускается вручную. См. [CI/CD: диагностика](../ci-cd/diagnostics.md#-diaghelm-test).

### 3. `verify.sh`

End-to-end проверка через внешний IP:

```bash
cd infrastructure
./scripts/verify.sh
```

Проверяет:

- Поды backend и frontend `Ready`.
- ServiceMonitor и ConfigMap'ы мониторинга созданы.
- Сайт открывается по `EXTERNAL-IP`.
- Статика проксируется как JS.
- `/api/products` возвращает JSON.

Если `verify.sh` падает на статике — та же причина, что у `test-frontend`: `proxy_pass` в nginx.

### 4. Ресурсы мониторинга

```bash
# ServiceMonitor создан
kubectl get servicemonitor -n default | grep momo-store

# ConfigMap с дашбордами
kubectl get configmap -n default momo-store-grafana-dashboards

# ConfigMap с алертами
kubectl get configmap -n monitoring momo-store-grafana-alerting

# PrometheusRule (legacy)
kubectl get prometheusrule -n default | grep momo-store
```

> **Обратите внимание на namespace:** дашборды — в `default`, алерты — в `monitoring`. Это не опечатка, см. [architecture.md](./architecture.md#monitoring).

### 5. Метрики собираются

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# → http://localhost:9090/targets
```

Ищите `serviceMonitor/default/momo-store-backend/0` — должен быть `UP`.

### 6. Дашборды в Grafana

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# → http://localhost:3000
```

**Dashboards → Browse** → фильтр по тегу `momo-store`. Должны быть:

- Momo Store — Overview
- Momo Store — Business
- Momo Store — Infrastructure

### 7. Алерты в Grafana

**Alerting → Alert rules** → папка `Infrastructure` → группа `node-health`. Должны быть четыре правила в статусе `Normal`.

### 8. Проверка сайта

```bash
kubectl get ingress -n default
# ADDRESS — EXTERNAL-IP ingress-nginx

curl -I http://<EXTERNAL-IP>/
curl -I http://<EXTERNAL-IP>/momo-store/js/app.82cde13b.js
curl -s http://<EXTERNAL-IP>/api/products | head
```

---

## Обновление образа

```bash
helm upgrade -i momo-store ./ \
  -f values.yaml -f values-<env>.yaml \
  --set backend.image.tag=1.2.3 \
  --set monitoring.alerting.email="${GRAFANA_SMTP_EMAIL}" \
  --atomic \
  --wait --timeout 5m
```

Или через `--set` из CI — так делает пайплайн:

```bash
--set backend.image.tag="${IMAGE_TAG}"
```

---

## Обновление только ConfigMap'ов мониторинга

Если меняли только дашборды или алерты — `helm upgrade` достаточно, но sidecar Grafana подхватит ConfigMap в течение ~30 секунд.

Если sidecar не подхватывает — рестарт:

```bash
kubectl rollout restart deploy -n monitoring monitoring-grafana
```

---

## Откат

```bash
helm history momo-store
helm rollback momo-store <revision>
```

**Важно:** `helm rollback` восстанавливает **все** ресурсы чарта, включая ConfigMap'ы мониторинга. Если после отката что-то сломалось — проверьте `--set monitoring.alerting.email` в текущем релизе.

---

## Удаление

```bash
helm uninstall momo-store -n default
```

**Что остаётся:**

- `PrometheusRule/momo-store-alerts` — **останется**, потому что Helm не удаляет CRD без аннотации. Удалить вручную:
  ```bash
  kubectl delete prometheusrule momo-store-alerts -n default
  ```
- Секрет `ycr-secret` — **останется** (создан вручную).
- Namespace `monitoring` — **останется** (там живут Prometheus и Grafana, они не часть чарта).

**Что удалится:**

- `Deployment`, `Service` для backend и frontend.
- `Ingress/momo-store-api` и `Ingress/momo-store-frontend`.
- `ServiceMonitor/momo-store-backend`.
- `ConfigMap/momo-store-grafana-dashboards` (в `default`).
- `ConfigMap/momo-store-grafana-alerting` (в `monitoring`).
- Тестовые поды `*-test-backend` и `*-test-frontend` (если остались).

---

## Troubleshooting

Если `helm upgrade` падает с ошибкой:

- [CI/CD: диагностика](../ci-cd/diagnostics.md) — как запускать `diag:*` для проверки инфраструктуры.
- [CI/CD: переменные](../ci-cd/variables.md) — что делать при `Forbidden` на RBAC.
- [Observability](../observability/readme.md) — проблемы с дашбордами, алертами, SMTP.

Самое частое:

| Ошибка | Причина | Решение |
|---|---|---|
| `monitoring.alerting.email is required` | Не передали `--set monitoring.alerting.email` | Добавить в команду |
| `Forbidden: cannot get resource "prometheusrules"` | У `ci-deployer` нет прав на CRD `monitoring.coreos.com` | Добавить право в `setup-ci-rbac.sh` (см. [variables.md](../ci-cd/variables.md#-kube_config_staging)) |
| `Forbidden: cannot get resource "configmaps" in namespace "monitoring"` | ConfigMap алертов создаётся в `monitoring`, а `ci-deployer` имеет `Role` только в `default` | **Способ А:** `kubectl create rolebinding ci-deployer-monitoring --clusterrole=edit --serviceaccount=default:ci-deployer -n monitoring`. **Способ Б:** заменить `namespace: monitoring` на `namespace: {{ .Release.Namespace }}` в `templates/monitoring/grafana-alerting.yaml` |
| `Error: UPGRADE FAILED: ... context deadline exceeded` | Поды не стали `Ready` за 5 минут | `kubectl describe pod` — смотреть probes, образ, ресурсы |
| `Error: cannot re-use a name that is still in use` | Релиз `momo-store` уже существует, но `helm list` его не видит | `helm list -n default --all` → `helm uninstall momo-store -n default` |
| `ImagePullBackOff` | Нет секрета `ycr-secret` или он в другом namespace | `kubectl create secret docker-registry ycr-secret ...` |

> **Про `Forbidden` на `configmaps` в `monitoring`:** у `ci-deployer` **должны** быть права в namespace `monitoring`. Если деплой идёт из CI и падает с этой ошибкой — см. [CI/CD: переменные → `KUBE_CONFIG_STAGING`](../ci-cd/variables.md#-kube_config_staging).

---

## Связанные документы

- [README чарта](./readme.md) — быстрый старт, проверки, удаление
- [Архитектура](./architecture.md) — компоненты, схема потоков
- [Values reference](./values-reference.md) — все ключи `values.yaml`
- [CI/CD: пайплайн](../ci-cd/readme.md) — как чарт деплоится из GitLab CI
- [CI/CD: диагностика](../ci-cd/diagnostics.md) — `diag:*`-джобы
- [Observability](../observability/readme.md) — Prometheus + Grafana