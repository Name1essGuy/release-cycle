# Модуль GitLab Runner

## 📋 Описание
Модуль создает виртуальную машину с установленным GitLab Runner в Docker и автоматической регистрацией в GitLab.

## 🎯 Что создает
- Виртуальную машину с Ubuntu 22.04
- Установленный Docker
- Контейнер с GitLab Runner
- Автоматически зарегистрированный Runner в GitLab

## 📥 Входные параметры (variables)

| Параметр | Тип | Описание | Обязательный |
| :--- | :--- | :--- | :--- |
| `environment` | string | Окружение (dev, staging, prod) | ✅ Да |
| `gitlab_url` | string | URL GitLab инстанса (по умолчанию `https://gitlab.net`) | ❌ Нет |
| `gitlab_token` | string | Токен для регистрации раннера | ✅ Да |
| `subnet_id` | string | ID подсети для VM | ✅ Да |
| `security_group_ids` | list(string) | ID security групп | ❌ Нет |
| `ssh_public_key` | string | Публичный SSH ключ для доступа к VM | ✅ Да |
| `ssh_private_key_path` | string | Путь к приватному SSH-ключу (по умолчанию `~/.ssh/id_rsa`) | ❌ Нет |
| `disk_size` | number | Размер диска в ГБ (по умолчанию 20) | ❌ Нет |
| `tags` | map(string) | Теги для ресурсов | ❌ Нет |

## 📤 Выходные данные (outputs)

| Выход | Описание |
| :--- | :--- |
| `ip` | Публичный IP адрес VM |
| `ssh` | Команда для SSH доступа к VM |

## 🔗 Получение токена для регистрации

1. Зайдите в ваш GitLab проект или группу
2. Перейдите в **Settings → CI/CD → Runners**
3. Скопируйте **Registration token** (начинается с `glrt-`)
4. Добавьте в `environments/<env>/terraform.tfvars`:

```hcl
gitlab_token = {
  staging = "glrt-xxxxxxxxxxxxxxxxxxxx"
}
gitlab_url = "https://your-gitlab-instance.com"
```

## ⚠️ Важные замечания

- Токен регистрации чувствительный - используйте sensitive = true в переменной
- VM имеет публичный IP для доступа к GitLab и реестрам
- Docker устанавливается автоматически при создании VM
- GitLab Runner работает в Docker-контейнере с перезапуском при сбоях
- Регистрация происходит автоматически через user-data скрипт


## 🚀 Использование в корневом модуле

```hcl
module "gitlab_runner" {
  source = "./modules/gitlab-runner"
  count  = local.environment != "dev" ? 1 : 0

  environment          = local.environment
  gitlab_url           = var.gitlab_url
  gitlab_token         = var.gitlab_token[local.environment]
  subnet_id            = module.networking.subnet_ids[0]
  security_group_ids   = [module.networking.gitlab_runner_security_group_id]
  ssh_public_key       = file(var.ssh_public_key_path)
  ssh_private_key_path = var.ssh_private_key_path
  disk_size            = 20
  tags                 = var.tags
}
```