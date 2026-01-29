# ⚠️ АРХИВ - Рефакторинг Terraform конфигурации (Январь 2026)

> **Статус:** Устарело - сохранено для истории  
> **Дата:** 2026-01-29  
> **Актуальная документация:** См. [changelog.md](../changelog.md)

**Примечание:** Этот документ описывает конкретный рефакторинг, выполненный в январе 2026. Важные выводы были перенесены в changelog.md. Документ сохранен для понимания эволюции проекта.

---

# Рефакторинг Terraform конфигурации

## Обзор изменений

Terraform конфигурация была рефакторирована для улучшения модульности, устранения циклических зависимостей и предотвращения нежелательного пересоздания ресурсов.

## Основные улучшения

### 1. Исправлена проблема пересоздания VM ✅

**Проблема:** При изменении xray конфигурации Terraform хотел пересоздать все VM из-за обновления `image_id` в data source.

**Решение:** Добавлены lifecycle правила в модули `team_vm` и `edge`:

```hcl
lifecycle {
  ignore_changes = [
    boot_disk[0].initialize_params[0].image_id
  ]
}
```

Теперь VM не будут пересоздаваться при обновлении образа Ubuntu в Yandex Cloud.

### 2. Новая модульная структура

#### До рефакторинга:
```
environments/dev/
└── main.tf (559 строк - всё в одном файле)
```

#### После рефакторинга:
```
environments/dev/
├── main.tf           # 218 строк - только инфраструктура
├── credentials.tf    # 29 строк - управление SSH ключами
└── config-sync.tf    # 24 строки - синхронизация конфигов

modules/
├── team-credentials/ # НОВЫЙ - генерация credentials файлов
├── config-sync/      # НОВЫЙ - синхронизация конфигов на серверы
├── team_vm/         # + lifecycle правила
└── edge/            # + lifecycle правила

templates/
└── team/            # НОВЫЙ
    └── ssh-config.tpl
```

### 3. Разделение ответственности

#### Модуль `team-credentials`
**Назначение:** Сохранение SSH ключей в файлы и генерация documentation

**Что содержит:**
- Сохранение приватных/публичных ключей для jump, VM, GitHub
- Генерация SSH конфигов из template
- Создание teams-credentials.json

**Преимущества:**
- Изолированное управление credentials
- Независимые обновления без влияния на инфраструктуру
- Переиспользование в других окружениях

#### Модуль `config-sync`
**Назначение:** Синхронизация конфигурационных файлов на серверы

**Что содержит:**
- Генерация Traefik dynamic configs (auto + custom)
- Синхронизация Xray конфигурации
- Синхронизация Traefik конфигов
- Синхронизация team jump ключей на bastion

**Преимущества:**
- Четкое разделение: создание инфраструктуры vs обновление конфигов
- Можно обновлять конфиги без изменения VM
- Легче отлаживать проблемы синхронизации

#### main.tf
**Назначение:** Создание основной инфраструктуры

**Что содержит:**
- Генерация SSH ключей (для разрыва циклических зависимостей)
- Network, Security Groups
- Edge VM (NAT + Bastion)
- Routing
- Team VMs

### 4. Устранение циклических зависимостей

**Проблема:** Циклическая зависимость между модулями:
- edge → team_credentials (нужны jump keys)
- team_credentials → team_vm (нужны private IPs)
- team_vm → edge (через network/routing)

**Решение:** Генерация SSH ключей вынесена в `main.tf` и выполняется на ранней стадии:

```hcl
# В main.tf - генерация ключей
resource "tls_private_key" "team_jump_key" { ... }
resource "tls_private_key" "team_vm_key" { ... }
resource "tls_private_key" "team_github_key" { ... }

# Передача в edge
module "edge" {
  team_jump_keys = [for key in tls_private_key.team_jump_key : key.public_key_openssh]
}

# Передача в team_credentials для сохранения в файлы
module "team_credentials" {
  team_jump_private_keys = { for k, v in tls_private_key.team_jump_key : k => v.private_key_openssh }
  team_jump_public_keys  = { for k, v in tls_private_key.team_jump_key : k => v.public_key_openssh }
}
```

### 5. Оптимизация зависимостей

Использование `terraform_data` для контроля обновлений SSH конфигов:

```hcl
resource "terraform_data" "team_ip_tracker" {
  for_each = var.teams
  input = {
    team_id    = each.key
    user       = each.value.user
    private_ip = each.value.private_ip
  }
}

resource "local_file" "team_ssh_config" {
  content = templatefile("...", {
    team_private_ip = terraform_data.team_ip_tracker[each.key].output.private_ip
  })
  depends_on = [terraform_data.team_ip_tracker]
}
```

## Применение изменений

### 1. Проверка изменений

```bash
cd environments/dev
terraform plan
```

Ожидаемые изменения:
- 16 ресурсов будут созданы (перемещение в модули)
- 1 ресурс обновится in-place (edge VM metadata)
- 15 ресурсов будут удалены (старые ресурсы вне модулей)
- **VM НЕ будут пересоздаваться**

### 2. Применение изменений

```bash
terraform apply
```

### 3. Обновление xray конфигурации

Теперь можно безопасно обновлять `secrets/xray-config.json`:

```bash
# Отредактируйте конфиг
vi ../../secrets/xray-config.json

# Примените изменения
terraform apply
```

Edge VM обновится in-place, team VM останутся без изменений.

## Преимущества новой структуры

1. **Решена проблема пересоздания VM** - lifecycle правила защищают от нежелательных recreate
2. **Модульность** - каждый модуль отвечает за свою область
3. **Независимость** - изменения credentials не влияют на инфраструктуру
4. **Читаемость** - main.tf сократился с 559 до 218 строк
5. **Переиспользование** - модули можно использовать в других окружениях
6. **Упрощенная отладка** - проще найти и исправить проблемы
7. **Нет циклических зависимостей** - Terraform plan работает быстро и предсказуемо

## Миграция с backup

Если что-то пойдет не так, можно восстановить из backup:

```bash
cd environments/dev
cp main.tf.backup main.tf
terraform init
terraform plan
```

## Следующие шаги

1. ✅ Добавить lifecycle правила в VM модули
2. ✅ Создать модуль team-credentials
3. ✅ Создать модуль config-sync
4. ✅ Разделить main.tf на части
5. ✅ Вынести SSH config в template
6. ✅ Оптимизировать зависимости через terraform_data
7. Протестировать в production окружении
8. Обновить CI/CD пайплайны при необходимости
