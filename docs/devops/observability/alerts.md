# Алерты

## 📋 Описание

Алерты в проекте работают через **Grafana Alerting** — встроенный механизм Grafana. Он **не зависит** от Prometheus Alertmanager (который отключён через `alertmanager.enabled=false`) и использует собственный SMTP для отправки писем.

Все алерты деплоятся через Helm-чарт `momo-store`, а не создаются вручную в UI. Это значит:

- При `helm upgrade` алерты автоматически обновляются.
- Изменения, сделанные в UI, будут перезаписаны при следующем деплое.
- Конфигурация алертов хранится в git — есть history и code review.

---

## 🏗 Как устроено

```
┌─────────────────────────────────────────┐
│ k8s/helm/momo-store/templates/          │
│   monitoring/grafana-alerting.yaml      │
│                                         │
│  ConfigMap momo-store-grafana-alerting  │
│    labels: grafana_alert: "1"           │
│    data:                                │
│      contact-points.yaml: ...           │
│      alert-rules.yaml: ...              │
│      notification-policies.yaml: ...    │
└──────────────────┬──────────────────────┘
                   │ helm upgrade
                   ▼
┌─────────────────────────────────────────┐
│ Sidecar grafana-sc-alerts               │
│ (контейнер рядом с Grafana)             │
│                                         │
│ Сканирует ConfigMap с меткой            │
│ grafana_alert=1 во всех namespace       │
│                                         │
│ Записывает файлы в                      │
│ /etc/grafana/provisioning/alerting/     │
└──────────────────┬──────────────────────┘
                   │ reload
                   ▼
┌─────────────────────────────────────────┐
│ Grafana Alerting                        │
│                                         │
│  • Contact points                       │
│  • Alert rules                          │
│  • Notification policies                │
│                                         │
│ Вычисляет правила → отправляет email    │
│ через SMTP (smtp.gmail.com:587)         │
└──────────────────┬──────────────────────┘
                   │
                   ▼
              ┌─────────┐
              │  Gmail  │
              └─────────┘
```

**Ключевые компоненты:**

- **ConfigMap** `momo-store-grafana-alerting` — содержит три provisioning-файла.
- **Метка `grafana_alert: "1"`** — по ней sidecar находит ConfigMap.
- **Sidecar `grafana-sc-alerts`** — контейнер в поде Grafana, читает ConfigMap и записывает файлы в `/etc/grafana/provisioning/alerting/`.
- **Grafana Alerting** — вычисляет правила и шлёт email.

---

## 📧 Contact Point

**Имя:** `gmail-alerts`
**Тип:** Email
**Адрес:** значение `GRAFANA_SMTP_EMAIL` (задаётся при `setup-monitoring.sh`)

```yaml
contactPoints:
  - orgId: 1
    name: gmail-alerts
    receivers:
      - uid: gmail-email
        type: email
        settings:
          addresses: "youremail@gmail.com"
          singleEmail: false
```

**Где посмотреть:** Grafana → **Alerting → Contact points → gmail-alerts**.

**Как проверить:** нажать **Test** — должно прийти тестовое письмо.

---

## 📢 Notification Policy

**Куда маршрутизируются алерты по умолчанию:**

```yaml
policies:
  - orgId: 1
    receiver: gmail-alerts
    group_by: ['alertname', 'severity']
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 4h
    routes: []
```

**Что это значит:**

- **Receiver:** `gmail-alerts` — все алерты идут на Gmail.
- **group_by:** `[alertname, severity]` — алерты группируются по имени и severity. Если сработали три алерта одного типа на разных нодах — будет **одно** письмо со списком.
- **group_wait:** `30s` — ждём 30 секунд после первого алерта, чтобы собрать группу.
- **group_interval:** `5m` — минимум 5 минут между обновлениями одной группы.
- **repeat_interval:** `4h` — если алерт висит, повторное письмо через 4 часа.
- **routes:** пусто — все алерты идут в default policy.

**Где посмотреть:** Grafana → **Alerting → Notification policies**.

---

## 🚨 Текущие алерты

Все алерты в папке **Infrastructure**, группа **node-health**.

### 1. Node CPU usage > 85%

**UID:** `node-high-cpu`
**Severity:** warning
**For:** 5m

**PromQL:**
```promql
(1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100
```

**Условие:** `> 85` (проценты)

**Что означает:** средняя загрузка CPU на ноде превысила 85% за последние 5 минут.

**Что делать:**
- Посмотреть, какой под жрёт CPU: `kubectl top pods -A --sort-by=cpu`.
- Проверить `momo-store-infrastructure` дашборд.
- Увеличить `resources.limits.cpu` для подозрительного пода.
- Или добавить нод в node group.

**Заголовок письма:**
```
[FIRING:1] Node CPU usage > 85% (node:cl1ahcdp6sq02m0st2lb-agac)
```

---

### 2. Node disk usage > 85%

**UID:** `node-disk-full`
**Severity:** warning
**For:** 10m

**PromQL:**
```promql
(1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) * 100
```

**Условие:** `> 85` (проценты)

**Что означает:** занято > 85% диска на одном из mountpoint'ов ноды.

**Что делать:**
- Посмотреть, что занимает место: `kubectl debug node/<node> -it --image=alpine` → `du -sh /*`.
- Очистить старые образы: `docker system prune` (или через `crictl`).
- Увеличить размер диска в node group.
- Проверить, не растёт ли `/var/log`.

**Почему `for: 10m`:** диск заполняется медленно. Не нужно будить по каждому всплеску.

**Почему `fstype!~"tmpfs|overlay"`:** исключаем виртуальные FS — они всегда занимают ~100%, но реального места не потребляют.

---

### 3. Node network receive errors

**UID:** `node-net-rx-errors`
**Severity:** warning
**For:** 5m

**PromQL:**
```promql
rate(node_network_receive_errs_total[5m])
```

**Условие:** `> 10` (ошибок/сек)

**Что означает:** на ноде больше 10 ошибок приёма сетевых пакетов в секунду.

**Что делать:**
- Проверить, на каком интерфейсе: label `device` в метрике.
- Возможные причины: проблема с драйвером, плохое качество сети, переполнение буферов.
- Обратиться в поддержку Yandex Cloud, если проблема повторяется.

**Как посмотреть источник:**
```promql
rate(node_network_receive_errs_total[5m]) > 0
```
Legend: `{{instance}} / {{device}}`.

---

### 4. Node network transmit errors

**UID:** `node-net-tx-errors`
**Severity:** warning
**For:** 5m

**PromQL:**
```promql
rate(node_network_transmit_errs_total[5m])
```

**Условие:** `> 10` (ошибок/сек)

**Что означает:** аналогично RX, только исходящие пакеты.

---

## 📂 Provisioning-файл

Все алерты, contact point и notification policy описаны в одном ConfigMap:

**`k8s/helm/momo-store/templates/monitoring/grafana-alerting.yaml`**

```yaml
data:
  contact-points.yaml: |
    apiVersion: 1
    contactPoints:
      - orgId: 1
        name: gmail-alerts
        receivers:
          - uid: gmail-email
            type: email
            settings:
              addresses: {{ .Values.monitoring.alerting.email | quote }}
              singleEmail: false

  alert-rules.yaml: |
    apiVersion: 1
    groups:
      - orgId: 1
        name: node-health
        folder: Infrastructure
        interval: 1m
        rules:
          - uid: node-high-cpu
            title: "Node CPU usage > 85%"
            condition: B
            data:
              - refId: A
                datasourceUid: prometheus
                model:
                  expr: (1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100
                  instant: true
              - refId: B
                datasourceUid: __expr__
                model:
                  type: threshold
                  expression: A
                  conditions:
                    - evaluator:
                        params: [85]
                        type: gt
                      operator: {type: and}
                      query: {params: [A]}
                      reducer: {type: last}
            noDataState: OK
            execErrState: Error
            for: 5m
            labels:
              severity: warning
              component: node
            annotations:
              summary: "High CPU on {{ $labels.instance }}"
              description: "CPU usage is {{ $value }}% for 5 minutes."
          # ... остальные три правила ...

  notification-policies.yaml: |
    apiVersion: 1
    policies:
      - orgId: 1
        receiver: gmail-alerts
        group_by: ['alertname', 'severity']
        group_wait: 30s
        group_interval: 5m
        repeat_interval: 4h
        routes: []
```

**Структура одного алерта:**

- **`uid`** — уникальный ID правила. По нему Grafana обновляет существующий алерт, а не создаёт дубликат.
- **`title`** — имя, которое видно в UI и в письме.
- **`condition`** — какой RefID является условием срабатывания (у нас B).
- **`data`** — массив запросов:
  - **RefID A:** Prometheus-запрос.
  - **RefID B:** threshold — сравнение с порогом.
- **`for`** — сколько условие должно держаться до срабатывания.
- **`labels`** — метки (severity, component).
- **`annotations`** — текст в письме.

---

## ✏️ Как изменить алерт

### Способ A — через Helm (правильный)

1. Откройте `k8s/helm/momo-store/templates/monitoring/grafana-alerting.yaml`.
2. Измените `params`, `for`, `title` и т.д. в нужном правиле.
3. `helm upgrade`:

   ```bash
   helm upgrade -i momo-store ./k8s/helm/momo-store \
     -f k8s/helm/momo-store/values.yaml \
     -f k8s/helm/momo-store/values-staging.yaml \
     --set monitoring.alerting.email="${GRAFANA_SMTP_EMAIL}"
   ```

4. Через 30 секунд sidecar подхватит изменения.

### Способ B — через UI (для теста)

1. Grafana → **Alerting → Alert rules** → открыть правило → **Edit**.
2. Изменить порог.
3. **Save**.

**Минус:** при следующем `helm upgrade` изменения затрёт provisioning.

---

## ➕ Как добавить новый алерт

### 1. Открыть provisioning-файл

`k8s/helm/momo-store/templates/monitoring/grafana-alerting.yaml`.

### 2. Добавить правило в группу `node-health`

Или создать **новую группу** (например, `app-health`):

```yaml
groups:
  - orgId: 1
    name: node-health
    folder: Infrastructure
    interval: 1m
    rules:
      # ... существующие правила ...

  - orgId: 1
    name: app-health
    folder: Momo Store
    interval: 1m
    rules:
      - uid: momo-backend-down
        title: "Momo Store backend down"
        condition: B
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: count(kube_pod_status_ready{namespace="default",pod=~"momo-store-backend-.*",condition="true"} == 1)
              instant: true
          - refId: B
            datasourceUid: __expr__
            model:
              type: threshold
              expression: A
              conditions:
                - evaluator:
                    params: [1]
                    type: lt
                  operator: {type: and}
                  query: {params: [A]}
                  reducer: {type: last}
        noDataState: Alerting
        execErrState: Error
        for: 2m
        labels:
          severity: critical
          component: app
        annotations:
          summary: "Momo Store backend has no ready pods"
```

### 3. Применить

```bash
helm upgrade -i momo-store ./k8s/helm/momo-store \
  -f k8s/helm/momo-store/values.yaml \
  -f k8s/helm/momo-store/values-staging.yaml \
  --set monitoring.alerting.email="${GRAFANA_SMTP_EMAIL}"
```

### 4. Проверить

```bash
# ConfigMap обновлён
kubectl get configmap -n monitoring momo-store-grafana-alerting -o yaml | grep 'uid:'

# Sidecar подхватил
kubectl logs -n monitoring deploy/monitoring-grafana -c grafana-sc-alerts --tail=10

# В Grafana
# Alerting → Alert rules → должна быть новая папка Momo Store
```

**Важно:** новый алерт попадёт в **default notification policy** → `gmail-alerts`. Дополнительно ничего настраивать не нужно.

---

## 🧪 Как проверить, что алерт работает

### Способ 1 — снизить порог временно

1. Открыть правило в provisioning-файле.
2. Поставить заведомо низкий порог: `params: [1]` вместо `[85]`.
3. `helm upgrade`.
4. Через 5 минут должно прийти письмо.
5. Вернуть порог обратно.

### Способ 2 — создать тестовый алерт

Добавить правило, которое всегда срабатывает:

```yaml
- uid: test-always-firing
  title: "TEST — always firing"
  condition: B
  data:
    - refId: A
      datasourceUid: prometheus
      model:
        expr: vector(1)
        instant: true
    - refId: B
      datasourceUid: __expr__
      model:
        type: threshold
        expression: A
        conditions:
          - evaluator:
              params: [0]
              type: gt
            operator: {type: and}
            query: {params: [A]}
            reducer: {type: last}
  noDataState: OK
  execErrState: Error
  for: 1m
  labels:
    severity: info
  annotations:
    summary: "Test alert"
```

Через 1 минуту письмо. Удалить после проверки.

### Способ 3 — Test в Contact Point

Grafana → **Alerting → Contact points → gmail-alerts → Test**.

Это **не проверяет** правила, только SMTP. Но полезно для быстрой диагностики.

---

## 🛠 Если письма не приходят

### 1. Проверить Contact Point

```bash
kubectl get configmap -n monitoring momo-store-grafana-alerting -o yaml | grep -A2 addresses
```

Должен быть **реальный** email, не placeholder.

### 2. Проверить SMTP в Grafana

```bash
kubectl exec -n monitoring deploy/monitoring-grafana -c grafana -- \
  grep -A10 '\[smtp\]' /etc/grafana/grafana.ini
```

Ожидаемо:

```ini
[smtp]
enabled = true
host = smtp.gmail.com:587
user = youremail@gmail.com
password = $__file{/etc/secrets/smtp-password/password}
from_address = youremail@gmail.com
from_name = Grafana
skip_verify = true
```

### 3. Проверить Secret

```bash
kubectl get secret -n monitoring grafana-smtp-secret
kubectl exec -n monitoring deploy/monitoring-grafana -c grafana -- \
  ls -la /etc/secrets/smtp-password/
```

### 4. Проверить Notification Policy

Grafana → **Alerting → Notification policies** → default policy → должен быть receiver `gmail-alerts`.

### 5. Проверить логи

```bash
kubectl logs -n monitoring deploy/monitoring-grafana -c grafana --tail=50 | grep -i 'smtp\|alert'
```

Там будут ошибки вида `Failed to send email: ...`.

### 6. Проверить, что правило реально сработало

Grafana → **Alerting → Alert rules** → открыть правило → вкладка **State history**.

Если там только `Normal` — условие не срабатывало. Временный алерт (Способ 2) поможет убедиться, что механизм работает.

---

## 🚫 Что не отправляется

В Grafana есть **ещё три правила**, созданные из `PrometheusRule` (`prometheusrule.yaml`):

- `MomoStoreHighLatencyP95`
- `MomoStoreBackendDown`
- `MomoStoreHighCpu`

Они видны в **Alerting → Alert rules** (папка `momo-store`), но:

- **Не отправляют email** — Alertmanager отключён.
- Создаются из `PrometheusRule`, а не из Grafana provisioning.
- Используются только для визуального контроля в UI.

Если нужно, чтобы и они отправляли письма — либо перенести их в Grafana Alerting, либо включить Alertmanager.

---

## 🔐 SMTP: Gmail App Password

### Как получить

1. Google Account → **Security**.
2. **2-Step Verification** → включить, если не включена.
3. **App passwords** → создать для Mail + Other (Grafana).
4. Скопировать 16-символьный пароль.

### Как передать в Grafana

1. Экспортировать при запуске `setup-monitoring.sh`:

   ```bash
   export GRAFANA_SMTP_PASSWORD="xxxx xxxx xxxx xxxx"
   ```

2. Скрипт создаст Secret `grafana-smtp-secret` в namespace `monitoring`.
3. Grafana монтирует Secret и читает пароль через `$__file{}`.

**Обычный пароль Gmail не подойдёт.**

---

## 📚 Ссылки

- [Observability: обзор](./readme.md)
- [Дашборды](./dashboards.md)
- [Grafana Alerting provisioning](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/) — формат provisioning
- [Gmail App Passwords](https://support.google.com/accounts/answer/185833) — как создать