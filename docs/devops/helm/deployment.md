# Деплой и обновление

## Предварительная проверка

### 1. ClusterIP kube-dns

```bash
kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}'
```

### 2. ID Security Group для LB

```bash
yc vpc security-group get --name <env>-sg-ingress-lb --format json | jq -r '.id'
```

Впишите в `values-<env>.yaml` → `ingress-nginx.controller.service.annotations."yandex.cloud/security-group-ids"`.


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

## Установка и обновление образа

```bash
helm upgrade -i momo-store ./ \
  -f values.yaml \
  -f values-<env>.yaml
```

## Откат

```bash
helm history momo-store
helm rollback momo-store <revision>
```