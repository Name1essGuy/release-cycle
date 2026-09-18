# Диагностический пайплайн

## 📋 Описание

В проекте есть **отдельный набор диагностических джоб**, который лежит в файле `ci/diagnostics.yml`. Он **не подключён** к основному пайплайну и запускается **только вручную** — когда нужно быстро проверить, что инфраструктура, секреты и кластер настроены правильно.

Диагностика покрывает всё, что нужно для деплоя:

- сеть до внешних ресурсов;
- Docker-in-docker;
- авторизацию в Container Registry;
- доступ к S3;
- доступ к Kubernetes-кластеру;
- валидность Helm-чарта.

Если что-то ломается в основном пайплайне, диагностика помогает быстро локализовать: **сеть, секреты, RBAC или Dockerfile**.

---

## 🎯 Когда использовать

- **Первый запуск пайплайна** в новом окружении или на новом раннере.
- **После пересоздания кластера Terraform'ом.**
- **После смены секретов** в GitLab (переменные, ключи).
- **При любой непонятной ошибке** в `push:*` или `deploy:*` — сначала диагностика, потом дебаг основной джобы.
- **Периодически** — раз в месяц, чтобы убедиться, что инфраструктура не разъехалась.

Не нужно запускать **на каждый push** — это замедляет CI и не даёт пользы, если ничего не менялось.

---

## 📁 Где лежит

```
momo-store/
├── .gitlab-ci.yml              # основной пайплайн (диагностика НЕ подключена)
└── ci/
    └── diagnostics.yml         # диагностические джобы (лежат отдельно)
```

`ci/diagnostics.yml` **не подключается через `include`** в `.gitlab-ci.yml`. Это сделано специально: при отладке мы столкнулись с тем, что `include` + свои `stages` в подключаемом файле конфликтуют с основным пайплайном (ошибка `chosen stage diagnostics does not exist`). Проще держать файл отдельно и включать вручную.

---

## 🚀 Как запустить

Есть **три способа**. Выбирайте по ситуации.

### Способ 1 — временная ветка (рекомендую)

Самый безопасный: основной `.gitlab-ci.yml` не трогается.

```bash
# 1. Создать ветку для диагностики
git checkout -b ci/run-diagnostics

# 2. Заменить основной пайплайн диагностическим
mv .gitlab-ci.yml .gitlab-ci.main.yml
cp ci/diagnostics.yml .gitlab-ci.yml

# 3. Запушить
git add .gitlab-ci.yml .gitlab-ci.main.yml
git commit -m "ci: run diagnostics"
git push origin ci/run-diagnostics
```

GitLab запустит диагностический пайплайн на ветке `ci/run-diagnostics`. После просмотра результатов:

```bash
# Вернуть всё обратно
git checkout ci/pipeline-dev
git branch -D ci/run-diagnostics
git push origin --delete ci/run-diagnostics
```

**Плюсы:** основной пайплайн не трогается, история изменений чистая.
**Минусы:** надо копировать файлы вручную.

### Способ 2 — временная правка `.gitlab-ci.yml`

Быстрее, но грязнее: в текущей ветке добавляется блок диагностики **с правилами запуска только вручную**.

В `.gitlab-ci.yml` (временная правка) добавить в начало:

```yaml
include:
  - local: '/ci/diagnostics.yml'
```

И в `stages:` добавить `diagnostics` **первой**:

```yaml
stages:
  - diagnostics
  - test
  - build
  - deploy
```

Затем в `ci/diagnostics.yml` добавить в начало:

```yaml
stages:
  - diagnostics
```

**Не надо** — `stages` должен быть **только в основном файле**. Если добавите в оба, будет ошибка. Уберите `stages` из `diagnostics.yml`, если он там есть.

Запушить. Пайплайн запустится, `diag:*` появятся, но с правилом `when: never` по умолчанию — **не запустятся автоматически**. Нужно запустить вручную через **Run pipeline** с переменной:

- Key: `RUN_DIAGNOSTICS`
- Value: `true` (запустятся все) или `manual` (запускаются кнопкой ▶).

**Плюсы:** не надо копировать файл.
**Минусы:** временная правка в `.gitlab-ci.yml`, которую надо не забыть откатить.

### Способ 3 — GitLab UI → Run pipeline

Если `.gitlab-ci.yml` **уже** содержит `include: ci/diagnostics.yml` (не наш случай, но можно настроить):

1. **CI/CD → Pipelines → Run pipeline**.
2. Выбрать ветку.
3. Variables:
   - Key: `RUN_DIAGNOSTICS`
   - Value: `true`
4. Run.

Запустятся только `diag:*` (если основной пайплайн не триггерится на этой ветке).

---

## 🔍 Что проверяет каждая джоба

### `diag:network`

**Что проверяет:** сетевую доступность внешних ресурсов, нужных пайплайну.

**Куда стучится:**

| Ресурс | URL | Зачем |
|---|---|---|
| GitLab | `https://praktikum.gitlab.yandexcloud.net` | Pull кода, регистрация runner |
| Container Registry | `https://cr.yandex` | Push/pull образов |
| S3 | `https://storage.yandexcloud.net` | Загрузка статики |
| registry.k8s.io | `https://registry.k8s.io` | Базовые образы Kubernetes |
| docker.io | `https://registry-1.docker.io` | Базовые образы Docker Hub |

**Ожидаемый результат:**

```
✅ GitLab OK
✅ cr.yandex OK
✅ S3 OK
✅ registry.k8s.io OK
✅ docker.io OK
```

**Если упало:** у runner'а нет egress-доступа в интернет. Проверьте SG `<env>-sg-gitlab-runner` — должно быть правило `egress ANY 0.0.0.0/0`. Или проблема с NAT — подсеть без route table.

### `diag:dind`

**Что проверяет:** Docker-in-docker работает.

**Что делает:**
- Запускает сервис `docker:27-dind`.
- Подключается к нему через `tcp://docker:2376`.
- Запускает `docker info` и `docker run --rm alpine:latest`.

**Ожидаемый результат:**

```
Server:
 Containers: ...
 Images: ...
dind works
```

**Если упало с `Cannot connect to the Docker daemon`:** на runner-ВМ в `/etc/gitlab-runner/config.toml` не установлено `privileged = true`. Проверьте:

```bash
sudo grep privileged /etc/gitlab-runner/config.toml
# должно быть: privileged = true
```

Если нет — дописать и перезапустить runner:

```bash
sudo nano /etc/gitlab-runner/config.toml
# добавить в [runners.docker]: privileged = true
sudo docker restart gitlab-runner
```

### `diag:registry-login`

**Что проверяет:** авторизация в `cr.yandex`.

**Что делает:**
- Декодирует `YC_SA_KEY_JSON` из base64.
- Делает `docker login` с этими кредами.

**Ожидаемый результат:**

```
login OK
```

**Если упало с `unauthorized: Password is invalid - must be JSON key`:**
- `YC_SA_KEY_JSON` содержит некорректный base64.
- Или ключ от другого SA, не от `staging-gitlab-runner-sa`.

Проверьте локально:

```bash
echo "<значение YC_SA_KEY_JSON>" | base64 -d | jq -r '.service_account_id'
# Должно вывести ID staging-gitlab-runner-sa
```

Если `jq` падает — base64 битый.

### `diag:s3`

**Что проверяет:** доступ к S3.

**Что делает:**
- Загружает тестовый файл `_ci_test.txt` в `s3://${S3_BUCKET}/`.
- Удаляет его.

**Ожидаемый результат:**

```
upload: ./test.txt to s3://momo-store-frontend/_ci_test.txt
delete: s3://momo-store-frontend/_ci_test.txt
✅ S3 works
```

**Если упало с `Access Denied`:** ключи `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` не имеют прав на бакет. Проверьте, что это ключи от SA `terraform-state-bucket-sa` (роль `storage.editor`).

### `diag:kubectl`

**Что проверяет:** доступ к Kubernetes-кластеру.

**Что делает:**
- Декодирует `KUBE_CONFIG_STAGING` из base64.
- Делает `kubectl get pods, deployments, services, ingress -n default`.

**Ожидаемый результат:**

```
staging
NAME                            READY   STATUS
momo-store-backend-xxx          1/1     Running
momo-store-frontend-xxx         1/1     Running
...
```

**Если упало с `Unauthorized`:** токен в kubeconfig невалидный. Пересоздайте через `setup-ci-rbac.sh`.

**Если упало с `Forbidden` на `nodes` или `clusterroles`:** это **правильно** — RBAC ограничен namespace `default`. Другие джобы не должны обращаться к cluster-wide ресурсам.

### `diag:helm-lint`

**Что проверяет:** Helm-чарт валиден.

**Что делает:** `helm lint k8s/helm/momo-store`.

**Ожидаемый результат:**

```
==> Linting k8s/helm/momo-store
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed
```

**Если упало:** ошибка в шаблонах чарта. Смотрите конкретное сообщение.

### `diag:helm-template`

**Что проверяет:** чарт рендерится с values-staging.

**Что делает:**
- `helm template momo-store ... -f values.yaml -f values-staging.yaml`.
- Сохраняет результат в `/tmp/rendered.yaml`.
- Показывает первые 50 строк.

**Ожидаемый результат:**

```
Rendered 200 lines
---
# Source: momo-store/templates/backend/deployment.yaml
...
```

**Если упало:** проблема в values (например, отсутствует обязательное поле). Смотрите `helm template` локально для деталей.

---

## 📊 Как читать результаты

### Все зелёные

Инфраструктура, секреты и кластер настроены правильно. Если основной пайплайн всё равно падает — проблема в **самом пайплайне**, а не в окружении. Смотрите `troubleshooting.md`.

### Одна красная

Понятно, что чинить:

| Красная джоба | Что чинить |
|---|---|
| `diag:network` | SG, NAT, egress runner'а |
| `diag:dind` | `privileged = true` в config.toml |
| `diag:registry-login` | `YC_SA_KEY_JSON`, права SA |
| `diag:s3` | `AWS_*` ключи, права на бакет |
| `diag:kubectl` | `KUBE_CONFIG_STAGING`, RBAC |
| `diag:helm-lint` | шаблоны чарта |
| `diag:helm-template` | values чарта |

### Несколько красных

Скорее всего, проблема на уровне **инфраструктуры** — например, runner не может ходить в интернет. Начинайте с `diag:network` — если сеть не работает, остальное тоже не заработает.

---

## 🎛 Диагностика вручную (без CI)

Если не хочется запускать пайплайн, те же проверки можно сделать на runner-ВМ:

```bash
# Сеть
curl -sI https://cr.yandex | head -1
curl -sI https://storage.yandexcloud.net | head -1

# Docker
sudo docker info
sudo docker run --rm alpine:latest echo "dind works"

# Registry
echo "$YC_SA_KEY_JSON" | base64 -d | docker login --username json_key --password-stdin cr.yandex

# S3
aws --endpoint-url=https://storage.yandexcloud.net s3 ls s3://momo-store-frontend/

# kubectl
echo "$KUBE_CONFIG_STAGING" | base64 -d > /tmp/kc
KUBECONFIG=/tmp/kc kubectl get pods -n default
```

---

## 🧹 После использования

**Если запускали через временную ветку** — удалить её:

```bash
git checkout ci/pipeline-dev
git branch -D ci/run-diagnostics
git push origin --delete ci/run-diagnostics
```

**Если временно правили `.gitlab-ci.yml`** — откатить:

```bash
git checkout .gitlab-ci.yml
```

Или вручную убрать `include: ci/diagnostics.yml` и `diagnostics` из `stages`.

---

## ⚠️ Частые проблемы

### Джобы не запускаются, висят в `pending`

**Причина:** теги runner'а не совпадают с `tags:` в джобах.

**Проверка:**

```bash
# В GitLab: Settings → CI/CD → Runners
# Посмотреть теги runner'а
```

Если у runner'а теги `docker, staging`, а в джобе `tags: [docker]` — не запустится. Или наоборот.

### Джобы видны, но не запускаются (серые)

**Причина:** в `ci/diagnostics.yml` правила `when: manual` без явного запуска.

**Решение:** в GitLab UI → Pipeline → нажать ▶ на нужной джобе. Или запустить пайплайн с `RUN_DIAGNOSTICS=true`.

### `diag:network` падает с `exit code 23`

**Причина:** `curl -sI ... | head -1` — pipe закрывается, `curl` возвращает 23 (write error).

**Решение:** заменить на `curl -sI --max-time 5 -o /dev/null "$url"` без pipe.

### `diag:helm-lint` падает с `Error: unknown command "sh" for "helm"`

**Причина:** образ `alpine/helm` имеет `ENTRYPOINT ["helm"]`, а GitLab вызывает `sh`.

**Решение:** использовать `image: alpine:3.20` + `before_script: apk add --no-cache helm`.

---

## 🔗 Ссылки

- [Основной пайплайн](./readme.md)
- [Переменные](./variables.md)
- [Troubleshooting](./troubleshooting.md)
- [GitLab Docs: CI/CD pipeline](https://docs.gitlab.com/ee/ci/pipelines/)