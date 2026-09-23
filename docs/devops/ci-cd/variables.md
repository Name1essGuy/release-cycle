# Переменные CI/CD

Все секреты и параметры пайплайна хранятся в **GitLab → Settings → CI/CD → Variables**. Ничего чувствительного не должно быть в `.gitlab-ci.yml` или в репозитории.

---

## 🔑 Обязательные переменные

| Key | Type | Masked | Protected | Откуда взять |
|---|---|---|---|---|
| `YC_SA_KEY_JSON` | Variable | ✅ | ❌ | `bootstrap/key.json`, закодированный в base64 |
| `AWS_ACCESS_KEY_ID` | Variable | ✅ | ❌ | `terraform output -raw access_key` из bootstrap |
| `AWS_SECRET_ACCESS_KEY` | Variable | ✅ | ❌ | `terraform output -raw secret_key` из bootstrap |
| `S3_BUCKET` | Variable | ❌ | ❌ | `momo-store-frontend` |
| `KUBE_CONFIG_STAGING` | Variable | ✅ | ❌ | Создаётся `setup-ci-rbac.sh` |
| `GRAFANA_SMTP_EMAIL` | Variable | ❌ | ❌ | Gmail-адрес для алертов |

> **Почему `Protected = false`.** Флаг `Protected` означает, что переменная доступна **только** в защищённых ветках (обычно `main`). У нас деплой запускается и из `ci/*` — а эти ветки не protected. Если поставить `Protected = true`, пайплайн на `ci/*` не получит переменные и упадёт. **Снимаем `Protected` со всех переменных**, пока работаем с `ci/*`. Когда перейдёте только на `main` — можно включить.

> **Почему `Masked` не работает для `YC_SA_KEY_JSON`, если он в JSON-форме.** GitLab не даёт включить Masked для значений с пробелами и переносами строк. Поэтому мы кодируем JSON в **base64** — получается одна строка без пробелов. Тогда Masked работает.

> **`GRAFANA_SMTP_EMAIL` обязательна только при `monitoring.alerting.enabled=true`** (по умолчанию — `true`). Если отключить `monitoring` в `values.yaml`, переменную можно не задавать. Но в боевом окружении её лучше иметь — иначе алерты уйдут в никуда.

---

## 🔐 `YC_SA_KEY_JSON`

**Назначение:** авторизация в Yandex Container Registry (`cr.yandex`) для push образов.

**Формат:** base64 от содержимого `key.json` (одна строка без переносов).

### Как получить

Ключ создаётся для сервисного аккаунта `staging-gitlab-runner-sa` (роли `container-registry.images.pusher`, `container-registry.images.puller`, `storage.editor`, `logging.writer`).

Если ключ ещё не создан:

```bash
yc iam key create \
  --service-account-name staging-gitlab-runner-sa \
  --output gitlab-runner-key.json
```

Проверить, что ключ — от правильного SA:

```bash
jq -r '.service_account_id' gitlab-runner-key.json
# Сравнить с ID staging-gitlab-runner-sa в консоли YC
```

Закодировать в base64 **одной строкой**:

```bash
base64 -w0 gitlab-runner-key.json
```

Скопировать вывод целиком — это значение для переменной.

### Как использовать в пайплайне

```yaml
before_script:
  - echo "$YC_SA_KEY_JSON" | base64 -d > /tmp/key.json
  - docker login --username json_key --password-stdin cr.yandex < /tmp/key.json
  - rm -f /tmp/key.json
```

### Проверка

```bash
# На своей машине, перед вставкой в GitLab
echo "<вставленное значение>" | base64 -d | jq -r '.service_account_id, .id'
# Должно вывести ID сервисного аккаунта и ID ключа
```

Если `jq` падает — base64 некорректный.

### Что делать, если упало с `unauthorized: Password is invalid`

1. Проверить, что base64 декодируется в валидный JSON:
   ```bash
   echo "<value>" | base64 -d | jq .
   ```
2. Проверить, что `service_account_id` совпадает с `staging-gitlab-runner-sa`.
3. Проверить, что у SA есть роль `container-registry.images.pusher`:
   ```bash
   yc resource-manager folder list-access-bindings <folder-id> | grep staging-gitlab-runner-sa
   ```

---

## 🔐 `AWS_ACCESS_KEY_ID` и `AWS_SECRET_ACCESS_KEY`

**Назначение:** доступ к S3 для загрузки статики фронтенда.

**Формат:** обычная строка (не base64).

### Как получить

Из bootstrap-модуля Terraform:

```bash
cd infrastructure/bootstrap
terraform output -raw access_key
terraform output -raw secret_key
```

Или из сохранённого `outputs.json`:

```bash
cat outputs.json | jq -r '.access_key.value'
cat outputs.json | jq -r '.secret_key.value'
```

### Как использовать в пайплайне

`AWS_ACCESS_KEY_ID` и `AWS_SECRET_ACCESS_KEY` автоматически читаются `aws-cli` внутри `frontend-uploader` — передаются как `-e` при `docker run`.

```yaml
docker run --rm \
  -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
  -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
  ...
```

### Проверка

```bash
# Локально
AWS_ACCESS_KEY_ID="<id>" AWS_SECRET_ACCESS_KEY="<secret>" \
  aws --endpoint-url=https://storage.yandexcloud.net s3 ls s3://momo-store-frontend/
# Должен вернуть список файлов (или пусто, если бакет пуст)
```

### Что делать, если упало с `Access Denied`

1. Проверить, что ключ от SA `terraform-state-bucket-sa` (у него роли `storage.editor`).
2. Проверить, что бакет `momo-store-frontend` существует:
   ```bash
   yc storage bucket list
   ```
3. Проверить, что у SA есть доступ к этому бакету (по умолчанию `storage.editor` даёт доступ ко всем бакетам каталога).

---

## 📦 `S3_BUCKET`

**Назначение:** имя бакета, в который загружается статика.

**Значение:** `momo-store-frontend`

**Формат:** строка.

**Masked:** не нужен — не секрет.

### Как использовать

```yaml
docker run --rm \
  -e S3_BUCKET="${S3_BUCKET}" \
  ...
```

---

## 📧 `GRAFANA_SMTP_EMAIL`

**Назначение:** email для contact point `gmail-alerts` в Grafana и для `from_address` в SMTP.

**Формат:** обычная строка — Gmail-адрес.

**Masked:** не нужен — это не секрет, а публичный адрес.

**Когда обязательна:** только при `monitoring.alerting.enabled=true` (по умолчанию — `true`). Если отключить `monitoring` в `values.yaml`, переменную можно не задавать.

**Где используется:**

- В `deploy:staging` — передаётся как `--set monitoring.alerting.email`.
- В `setup-monitoring.sh` — передаётся как `--set grafana.grafana.ini.smtp.user` и `from_address`.

**Как получить:** ваш собственный Gmail-адрес.

**Проверка:**

```bash
kubectl get configmap -n monitoring momo-store-grafana-alerting \
  -o jsonpath='{.data.contact-points\.yaml}' | grep addresses
# Должен вернуть реальный email, не placeholder
```

**Что делать, если `deploy:staging` падает с `monitoring.alerting.email is required`:**

1. Проверить, что переменная задана в GitLab:
   ```bash
   curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
     "https://praktikum.gitlab.yandexcloud.net/api/v4/projects/${GITLAB_PROJECT_ID}/variables/GRAFANA_SMTP_EMAIL" \
     | jq '.key, .value'
   ```
2. Проверить, что она **не Masked** (для email Masked не имеет смысла).
3. Проверить, что в `.gitlab-ci.yml` в `deploy:staging` есть `--set monitoring.alerting.email="${GRAFANA_SMTP_EMAIL}"`.

---

## ☸️ `KUBE_CONFIG_STAGING`

**Назначение:** доступ к Kubernetes-кластеру для `helm upgrade` и `kubectl rollout`.

**Формат:** base64 от содержимого kubeconfig (одна строка).

### Как получить

**Автоматически** — через `setup-ci-rbac.sh`:

```bash
cd infrastructure
export GITLAB_TOKEN="glpat-xxxx"
export GITLAB_PROJECT_ID="5766"
export GITLAB_URL="https://praktikum.gitlab.yandexcloud.net"

./scripts/setup-ci-rbac.sh staging
```

Скрипт:
1. Создаст `ServiceAccount/ci-deployer`, `Role`, `RoleBinding`, `Secret` в кластере.
2. Соберёт kubeconfig с долгоживущим токеном.
3. Закодирует его в base64.
4. Через GitLab API создаст/обновит переменную `KUBE_CONFIG_STAGING`.

Если GitLab API вернёт `403` — скрипт выведет base64 в консоль, и его нужно вставить вручную.

**Вручную** — если `setup-ci-rbac.sh` не сработал:

```bash
# 1. Админский kubeconfig
yc managed-kubernetes cluster get-credentials \
  --name staging-managed-k8s --external --force

# 2. Создать SA, Role, RoleBinding (см. setup-ci-rbac.sh)

# 3. Получить токен
TOKEN=$(kubectl get secret ci-deployer-token -n default -o jsonpath='{.data.token}' | base64 -d)
CA_DATA=$(kubectl get secret ci-deployer-token -n default -o jsonpath='{.data.ca\.crt}')
CLUSTER_SERVER=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')

# 4. Собрать kubeconfig
cat > /tmp/kubeconfig-ci <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CA_DATA}
    server: ${CLUSTER_SERVER}
  name: staging
contexts:
- context:
    cluster: staging
    namespace: default
    user: ci-deployer
  name: staging
current-context: staging
users:
- name: ci-deployer
  user:
    token: ${TOKEN}
EOF

# 5. Закодировать
base64 -w0 /tmp/kubeconfig-ci
```

### Как использовать в пайплайне

```yaml
before_script:
  - echo "$KUBE_CONFIG_STAGING" | base64 -d > /tmp/kubeconfig
  - chmod 600 /tmp/kubeconfig
  - export KUBECONFIG=/tmp/kubeconfig
```

### Проверка

```bash
# На своей машине
echo "<value>" | base64 -d > /tmp/check-kubeconfig
KUBECONFIG=/tmp/check-kubeconfig kubectl get pods -n default
# Должен вернуть список подов (или пусто)

KUBECONFIG=/tmp/check-kubeconfig kubectl get nodes
# Должно упасть с Forbidden — это правильно, RBAC ограничен namespace default
```

### Что делать, если упало с `Unauthorized` или `Forbidden`

**`Unauthorized` (401)** — токен невалидный или не тот. Проверьте:
- Secret `ci-deployer-token` существует: `kubectl get secret ci-deployer-token -n default`.
- Токен в нём не пустой: `kubectl get secret ci-deployer-token -n default -o jsonpath='{.data.token}' | base64 -d | head -c 50`.

**`Forbidden` (403) на namespace default** — Role/RoleBinding не применились. Проверьте:
```bash
kubectl get role,rolebinding -n default | grep ci-deployer
```

**`Forbidden` на `prometheusrules` или `servicemonitors`** — `Role` не содержит права на CRD `monitoring.coreos.com`. Добавьте в `setup-ci-rbac.sh`:
```yaml
- apiGroups: ["monitoring.coreos.com"]
  resources: ["prometheusrules", "servicemonitors", "podmonitors"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```
и перезапустите скрипт.

**`Forbidden` на `configmaps` в namespace `monitoring`** — `ConfigMap/momo-store-grafana-alerting` создаётся **не** в namespace релиза (`default`), а в `monitoring` (там, где sidecar Grafana). У `ci-deployer` есть `Role` только в `default` — прав на `monitoring` нет.

Два способа починить:

**Способ А** — выдать `ci-deployer` права в namespace `monitoring`:

```bash
kubectl create rolebinding ci-deployer-monitoring \
  --clusterrole=edit \
  --serviceaccount=default:ci-deployer \
  -n monitoring
```

**Способ Б** — создавать ConfigMap в namespace релиза (`default`). В `templates/monitoring/grafana-alerting.yaml` заменить `namespace: monitoring` на `namespace: {{ .Release.Namespace }}`. Тогда sidecar Grafana должен искать ConfigMap во всех namespace (`searchNamespace=ALL`).

Способ А — быстрее и не трогает чарт. Способ Б — чище архитектурно, но требует настройки sidecar'а.

**`Forbidden` на `clusterroles` или `nodes`** — это **правильно**. RBAC ограничен namespace `default`. Если какая-то джоба пытается трогать cluster-wide ресурсы — это неправильно, надо убрать.

---

## 📋 Все переменные одной таблицей

| Key | Type | Masked | Protected | Источник |
|---|---|---|---|---|
| `YC_SA_KEY_JSON` | Variable | ✅ | ❌ | `base64 -w0 key.json` |
| `AWS_ACCESS_KEY_ID` | Variable | ✅ | ❌ | bootstrap → `access_key` |
| `AWS_SECRET_ACCESS_KEY` | Variable | ✅ | ❌ | bootstrap → `secret_key` |
| `S3_BUCKET` | Variable | ❌ | ❌ | `momo-store-frontend` |
| `KUBE_CONFIG_STAGING` | Variable | ✅ | ❌ | `setup-ci-rbac.sh` |
| `GRAFANA_SMTP_EMAIL` | Variable | ❌ | ❌ | ваш Gmail |

---

## 🔖 Встроенные переменные GitLab

Эти переменные GitLab задаёт автоматически — их **не надо** добавлять в Settings.

| Переменная | Когда заполнена | Что содержит |
|---|---|---|
| `CI_COMMIT_SHORT_SHA` | всегда | Короткий SHA коммита (8 символов) |
| `CI_COMMIT_BRANCH` | push в ветку | Имя ветки (`main`, `ci/...`, `feature/...`) |
| `CI_COMMIT_TAG` | push git-тега | Имя тега (`v1.2.3`) — **пусто** при push в ветку |

В `push:*` и `deploy:*` используются **все три**:

- `$CI_COMMIT_BRANCH` — для выбора ветки.
- `$CI_COMMIT_TAG` — для определения, что это релиз.
- `$CI_COMMIT_SHORT_SHA` — для Docker-тега в обычном push.

---

## 🛠 Как добавить переменную в GitLab

### Через UI

1. Открыть проект в GitLab: `https://praktikum.gitlab.yandexcloud.net/Name1ess_One/momo-store`.
2. **Settings → CI/CD → Variables → Add variable**.
3. Заполнить:
   - **Key** — имя переменной (например, `YC_SA_KEY_JSON`).
   - **Value** — значение (без кавычек, без лишних пробелов).
   - **Type** — `Variable` (или `File` для многострочных).
   - **Flags** — поставить `Masked` (если значение — одна строка без пробелов) и/или `Protected`.
   - **Environment scope** — оставить `*` (все окружения).
4. Save.

### Через API

```bash
curl --request POST \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  --form "key=YC_SA_KEY_JSON" \
  --form "value=${VALUE}" \
  --form "masked=true" \
  --form "protected=false" \
  "https://praktikum.gitlab.yandexcloud.net/api/v4/projects/${GITLAB_PROJECT_ID}/variables"
```

Если переменная уже существует — метод `PUT` вместо `POST`, URL с `/variables/${KEY}`.

### Проверить, что переменные заданы

```bash
curl -s --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://praktikum.gitlab.yandexcloud.net/api/v4/projects/${GITLAB_PROJECT_ID}/variables" \
  | jq -r '.[] | "\(.key)\tmasked=\(.masked)\tprotected=\(.protected)"'
```

Ожидаемый вывод:

```
YC_SA_KEY_JSON          masked=true     protected=false
AWS_ACCESS_KEY_ID       masked=true     protected=false
AWS_SECRET_ACCESS_KEY   masked=true     protected=false
S3_BUCKET               masked=false    protected=false
KUBE_CONFIG_STAGING     masked=true     protected=false
GRAFANA_SMTP_EMAIL      masked=false    protected=false
```

---

## 🚫 Чего не должно быть в переменных

- **Переносов строк** для Masked-переменных. Masked не даст сохранить значение с `\n`. Используйте base64 — одна строка без переносов.
- **Trailing newline** (`cat` часто добавляет `\n`). Используйте `base64 -w0` или `tr -d '\n'`.
- **Пробелов в начале или конце** значения. GitLab сохранит их, и пайплайн получит строку с пробелами — упадёт `docker login` или `kubectl`.
- **Кавычек** вокруг значения. GitLab сохранит их как часть значения — тоже упадёт.

---

## 🔗 Ссылки

- [Основной пайплайн](./readme.md)
- [Диагностика](./diagnostics.md) — как запускать `diag:*`-джобы, в том числе `diag:monitoring`
- [Helm: деплой и troubleshooting](../helm/deployment.md) — что делать при `Forbidden` на `configmaps` и при провале `helm upgrade`
- [Infrastructure: CI/CD RBAC](../infrastructure/readme.md) — что создаёт `setup-ci-rbac.sh`
- [GitLab Docs: Predefined variables](https://docs.gitlab.com/ee/ci/variables/predefined_variables.html)
- [GitLab Docs: CI/CD Variables](https://docs.gitlab.com/ee/ci/variables/)