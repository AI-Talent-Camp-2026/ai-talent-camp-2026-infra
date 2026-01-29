# Руководство разработчика

> **Последнее обновление:** 2026-01-29  
> **Связанные документы:** [modules.md](modules.md), [changelog.md](changelog.md)

## Обзор

Это руководство для контрибьюторов и разработчиков, работающих с AI Talent Camp Infrastructure.

---

## Содержание

- [Структура проекта](#структура-проекта)
- [Стандарты кодирования](#стандарты-кодирования)
- [Разработка модулей](#разработка-модулей)
- [Тестирование](#тестирование)
- [Процесс contribution](#процесс-contribution)
- [Обновление документации](#обновление-документации)

---

## Структура проекта

```
ai-talent-camp-2026-infra/
├── modules/                    # Terraform модули
│   ├── network/               # VPC и подсети
│   ├── security/              # Security groups
│   ├── routing/               # Route tables
│   ├── edge/                  # Edge/NAT VM
│   ├── team_vm/               # VM для команд
│   ├── team-credentials/      # Управление credentials
│   └── config-sync/           # Синхронизация конфигов
│
├── environments/              # Окружения
│   └── dev/                  # Development environment
│       ├── main.tf           # Основная конфигурация
│       ├── variables.tf      # Переменные
│       ├── outputs.tf        # Outputs
│       ├── credentials.tf    # Credentials management
│       └── config-sync.tf    # Config sync
│
├── templates/                 # Конфигурационные шаблоны
│   ├── traefik/              # Traefik configs
│   ├── xray/                 # Xray config template
│   └── team/                 # Team SSH configs
│
├── docs/                      # Документация
│   ├── quickstart.md         # Быстрый старт
│   ├── architecture.md       # Архитектура
│   ├── admin-guide.md        # Руководство администратора
│   ├── user-guide.md         # Руководство пользователя
│   ├── xray-configuration.md # Конфигурация Xray
│   ├── troubleshooting.md    # Решение проблем
│   ├── modules.md            # Документация модулей
│   ├── changelog.md          # История изменений
│   └── development.md        # Это руководство
│
├── secrets/                   # Gitignored - генерируемые ключи
│   ├── team-01/
│   ├── team-02/
│   ├── xray-config.json
│   └── traefik-dynamic.yml
│
├── .gitignore
├── provider.tf                # Provider configuration
├── variables.tf               # Root variables
├── outputs.tf                 # Root outputs
└── README.md                  # Главная страница
```

---

## Стандарты кодирования

### Terraform

#### Форматирование

```bash
# Всегда форматировать перед commit
terraform fmt -recursive
```

#### Naming conventions

**Resources:**
```hcl
# Pattern: <type>_<name>
resource "yandex_vpc_network" "this" { }
resource "yandex_compute_instance" "edge" { }
resource "local_file" "team_ssh_config" { }
```

**Variables:**
```hcl
# Используйте snake_case
variable "team_cores" { }
variable "public_subnet_id" { }
```

**Modules:**
```hcl
# Используйте kebab-case для имен модулей
module "team-credentials" { }
module "config-sync" { }
```

#### Комментарии

```hcl
# Хорошо: Объясняет "почему"
# Создаем route table отдельно чтобы избежать циклической зависимости
resource "yandex_vpc_route_table" "nat" {
  # ...
}

# Плохо: Описывает "что" (очевидно из кода)
# Создать route table
resource "yandex_vpc_route_table" "nat" {
  # ...
}
```

#### Variables

```hcl
variable "example" {
  description = "Clear description of purpose"
  type        = string
  default     = "value"  # Если не требуется - не указывать default
  
  validation {
    condition     = length(var.example) > 0
    error_message = "Example must not be empty."
  }
}
```

#### Outputs

```hcl
output "example" {
  description = "Clear description of what this outputs"
  value       = resource.type.name.attribute
  sensitive   = false  # true для секретов
}
```

---

## Разработка модулей

### Структура модуля

Каждый модуль должен содержать:

```
module-name/
├── main.tf           # Основные ресурсы
├── variables.tf      # Входные переменные
├── outputs.tf        # Outputs
├── versions.tf       # Provider versions (опционально)
└── README.md         # Документация модуля (опционально)
```

### Принципы

1. **Single Responsibility** - модуль должен решать одну задачу
2. **Reusable** - модуль должен быть переиспользуемым
3. **Well-documented** - clear variables и outputs
4. **Tested** - проверен на работоспособность

### Пример: Создание нового модуля

Допустим, нужно создать модуль для monitoring.

**1. Создать структуру:**
```bash
mkdir -p modules/monitoring
cd modules/monitoring
touch main.tf variables.tf outputs.tf versions.tf
```

**2. Определить variables:**
```hcl
# variables.tf
variable "name" {
  description = "Base name for monitoring resources"
  type        = string
}

variable "targets" {
  description = "List of VMs to monitor"
  type        = list(string)
}
```

**3. Создать ресурсы:**
```hcl
# main.tf
resource "yandex_monitoring_dashboard" "main" {
  name = "${var.name}-dashboard"
  # ...
}
```

**4. Определить outputs:**
```hcl
# outputs.tf
output "dashboard_url" {
  description = "URL of monitoring dashboard"
  value       = yandex_monitoring_dashboard.main.url
}
```

**5. Документировать:**
```hcl
# Добавить в docs/modules.md описание модуля
```

**6. Использовать:**
```hcl
# environments/dev/main.tf
module "monitoring" {
  source  = "../../modules/monitoring"
  name    = var.name
  targets = [module.edge.edge_instance_id]
}
```

---

## Тестирование

### Manual Testing

```bash
cd environments/dev

# 1. Проверить форматирование
terraform fmt -check -recursive

# 2. Валидация
terraform init
terraform validate

# 3. Plan (без изменений)
terraform plan

# 4. Применить в test окружении
terraform apply -auto-approve

# 5. Проверить работоспособность
# - SSH подключение
# - HTTP/HTTPS routing
# - Xray proxy

# 6. Cleanup
terraform destroy -auto-approve
```

### Testing Checklist

- [ ] `terraform fmt -check` проходит
- [ ] `terraform validate` проходит
- [ ] `terraform plan` не показывает неожиданных изменений
- [ ] SSH подключение работает
- [ ] Интернет работает на team VM
- [ ] TPROXY работает (AI API доступны)
- [ ] Traefik routing работает
- [ ] Документация обновлена

---

## Процесс contribution

### Workflow

```
1. Fork репозитория
     ↓
2. Создать feature branch
     ↓
3. Внести изменения
     ↓
4. Тестировать
     ↓
5. Commit с хорошим message
     ↓
6. Push и создать Pull Request
     ↓
7. Code review
     ↓
8. Merge
```

### Branch Naming

```
feature/add-monitoring       # Новая функция
fix/edge-vm-networking       # Исправление бага
docs/update-quickstart       # Обновление документации
refactor/simplify-modules    # Рефакторинг
```

### Commit Messages

**Формат:**
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: новая функция
- `fix`: исправление бага
- `docs`: изменения в документации
- `style`: форматирование (не влияет на код)
- `refactor`: рефакторинг кода
- `test`: добавление тестов
- `chore`: обновление build процесса и т.д.

**Примеры:**
```
feat(edge): add monitoring dashboard

Добавлен Yandex Monitoring dashboard для edge VM.
Отображает CPU, RAM, network traffic.

Closes #42

---

fix(xray): add proxy server IP to TPROXY exclusions

Исправлена проблема петли маршрутизации когда proxy IP
не был исключен из TPROXY.

Fixes #56

---

docs(quickstart): improve SSH setup instructions

Добавлены более подробные инструкции для Variant B.
```

### Pull Request

**Checklist:**
- [ ] Код отформатирован (`terraform fmt`)
- [ ] Тесты пройдены
- [ ] Документация обновлена
- [ ] CHANGELOG.md обновлен (для feature/fix)
- [ ] PR description описывает изменения
- [ ] Screenshots добавлены (если UI изменения)

**Template:**
```markdown
## Description
Краткое описание изменений.

## Changes
- Добавлено X
- Изменено Y
- Исправлено Z

## Testing
Как тестировать:
1. terraform apply
2. Проверить X
3. Проверить Y

## Screenshots
(если применимо)

## Checklist
- [x] Код отформатирован
- [x] Тесты пройдены
- [x] Документация обновлена
- [x] CHANGELOG.md обновлен
```

---

## Обновление документации

### Принципы

1. **Single Source of Truth** - каждый факт описан в одном месте
2. **Up-to-date** - документация обновляется вместе с кодом
3. **Clear** - понятно для целевой аудитории
4. **Actionable** - содержит практические примеры

### Структура документа

```markdown
# Название

> **Статус:** Актуально | Черновик | Устарело
> **Последнее обновление:** YYYY-MM-DD
> **Связанные документы:** [link1](link1.md), [link2](link2.md)

## Обзор
1-2 параграфа с кратким описанием.

## Содержание
- [Раздел 1](#раздел-1)
- [Раздел 2](#раздел-2)

## Раздел 1
Подробное описание с примерами.

## См. также
- [Related doc](related.md)
```

### Где документировать что

| Тема | Файл |
|------|------|
| Быстрый старт для команд | [quickstart.md](quickstart.md) |
| Архитектура | [architecture.md](architecture.md) |
| Администрирование | [admin-guide.md](admin-guide.md) |
| Использование инфраструктуры | [user-guide.md](user-guide.md) |
| Конфигурация Xray | [xray-configuration.md](xray-configuration.md) |
| Решение проблем | [troubleshooting.md](troubleshooting.md) |
| Описание модулей | [modules.md](modules.md) |
| История изменений | [changelog.md](changelog.md) |
| Для разработчиков | [development.md](development.md) |

### Checklist при изменении кода

- [ ] Обновлена документация (если применимо)
- [ ] Обновлен CHANGELOG.md (для user-facing изменений)
- [ ] Проверены ссылки (если менялась структура)
- [ ] Обновлены примеры кода

### Проверка документации

```bash
# Проверить ссылки (если установлен markdown-link-check)
find docs -name "*.md" -exec markdown-link-check {} \;

# Проверить орфографию
# (использовать spell checker вашего редактора)

# Проверить форматирование markdown
markdownlint docs/
```

---

## Инструменты разработки

### Рекомендуемые

- **Terraform** >= 1.0
- **Yandex Cloud CLI** (`yc`)
- **Git**
- **Code editor** (VS Code, IntelliJ с Terraform plugin)
- **jq** - для работы с JSON
- **yq** - для работы с YAML

### VS Code Extensions

- HashiCorp Terraform
- markdownlint
- GitLens
- YAML

### Полезные команды

```bash
# Terraform
terraform fmt -recursive          # Форматирование
terraform validate                # Валидация
terraform plan -out=tfplan        # Plan с сохранением
terraform show tfplan             # Просмотр saved plan

# Git
git log --oneline --graph         # История коммитов
git diff HEAD~1                   # Diff с предыдущим commit

# Yandex Cloud
yc compute instance list          # Список VM
yc vpc network list               # Список VPC
```

---

## Release Process

### 1. Подготовка

```bash
# Убедиться что main branch актуален
git checkout main
git pull origin main

# Создать release branch
git checkout -b release/v2.1.0
```

### 2. Обновить документацию

- Обновить [CHANGELOG.md](changelog.md)
- Обновить версию в README.md (если есть)
- Проверить, что документация актуальна

### 3. Тестирование

```bash
cd environments/dev
terraform plan
# Проверить, что нет неожиданных изменений

# Полный цикл в test окружении
terraform apply
# Тестировать функционал
terraform destroy
```

### 4. Создать tag

```bash
git add .
git commit -m "chore: prepare release v2.1.0"
git push origin release/v2.1.0

# После merge в main
git tag -a v2.1.0 -m "Release v2.1.0"
git push origin v2.1.0
```

### 5. GitHub Release

- Создать release на GitHub
- Скопировать changelog для этой версии
- Attach artifacts (если есть)

---

## Troubleshooting Development Issues

### Terraform state locked

```bash
# Если terraform apply был прерван
terraform force-unlock <lock-id>

# Или удалить state lock вручную (Yandex Object Storage)
```

### Changes not applying

```bash
# Проверить, что используется правильное окружение
pwd
# Должно быть: .../environments/dev/

# Проверить backend
terraform init -reconfigure
```

### Module not found

```bash
# Переинициализировать
terraform init -upgrade
```

---

## См. также

- [modules.md](modules.md) - детальное описание модулей
- [changelog.md](changelog.md) - история изменений
- [architecture.md](architecture.md) - архитектура проекта
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [Keep a Changelog](https://keepachangelog.com/ru/1.0.0/)
- [Semantic Versioning](https://semver.org/lang/ru/)
