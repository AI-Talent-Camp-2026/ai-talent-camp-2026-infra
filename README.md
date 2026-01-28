# AI Camp Infrastructure

Terraform-инфраструктура для AI-Camp хакатона в Yandex Cloud.

## Описание

Проект создает безопасную и управляемую инфраструктуру с:

- **Edge/NAT сервером** - единственная точка входа с публичным IP
- **Traefik** - reverse proxy с TLS passthrough
- **Xray/VLESS** - прозрачное проксирование AI API (OpenAI, Anthropic и др.)
- **Private Network** - изолированная сеть для команд
- **Team VMs** - отдельные VM для каждой команды

## Архитектура

```
                    Internet
                        │
                        ▼
              ┌───────────────────────┐
              │      DNS Records      │
              │ *.camp.aitalenthub.ru │
              └────────┬──────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────┐
│                   Yandex Cloud VPC                   │
│  ┌────────────────────────────────────────────────┐  │
│  │              Public Subnet (10.0.1.0/24)       │  │
│  │  ┌──────────────────────────────────────────┐  │  │
│  │  │            Edge/NAT VM                   │  │  │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  │  │  │
│  │  │  │ Traefik │  │  Xray   │  │   NAT   │  │  │  │
│  │  │  └─────────┘  └─────────┘  └─────────┘  │  │  │
│  │  └──────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────┘  │
│                          │                           │
│                          │ NAT + Routing             │
│                          ▼                           │
│  ┌────────────────────────────────────────────────┐  │
│  │             Private Subnet (10.0.2.0/24)       │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐     │  │
│  │  │ Team01   │  │ Team02   │  │ Team...  │     │  │
│  │  │   VM     │  │   VM     │  │   VM     │     │  │
│  │  └──────────┘  └──────────┘  └──────────┘     │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

## Prerequisites

### Обязательные

- **Terraform** >= 1.0
  ```bash
  # Установка на Linux
  wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
  unzip terraform_1.6.0_linux_amd64.zip
  sudo mv terraform /usr/local/bin/
  ```

- **Yandex Cloud CLI** (`yc`)
  ```bash
  curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash
  ```

- **SSH клиент** (обычно предустановлен)

### Опциональные

- **jq** - для парсинга JSON outputs
  ```bash
  sudo apt install jq
  ```

## Настройка Yandex Cloud

### 1. Создание сервисного аккаунта

```bash
# Авторизация
yc init

# Создать сервисный аккаунт
yc iam service-account create --name terraform-sa

# Назначить роль editor
yc resource-manager folder add-access-binding <folder-id> \
  --role editor \
  --subject serviceAccount:<service-account-id>

# Создать authorized key
yc iam key create \
  --service-account-name terraform-sa \
  --output key.json
```

### 2. Настройка переменных окружения

```bash
export YC_TOKEN=$(yc iam create-token)
export YC_CLOUD_ID=$(yc config get cloud-id)
export YC_FOLDER_ID=$(yc config get folder-id)
```

Или через service account key:

```bash
export YC_SERVICE_ACCOUNT_KEY_FILE=/path/to/key.json
```

## Quick Start

### 1. Клонировать репозиторий

```bash
git clone <repo-url>
cd iac/environments/dev
```

### 2. Настроить переменные

```bash
cp terraform.tfvars.example terraform.tfvars
```

Отредактируйте `terraform.tfvars`:

```hcl
folder_id       = "your-folder-id"
jump_public_key = "ssh-ed25519 AAAA... your-email@example.com"

teams = {
  "01" = {
    user        = "team01"
    public_keys = ["ssh-ed25519 AAAA... team01@example.com"]
  }
}
```

### 3. Инициализация и применение

```bash
terraform init
terraform plan
terraform apply
```

### 4. Получить outputs

```bash
# Все outputs
terraform output

# Публичный IP edge
terraform output edge_public_ip

# SSH команды для подключения
terraform output team_ssh_commands
```

## Структура проекта

```
iac/
├── modules/
│   ├── network/          # VPC и подсети
│   ├── security/         # Security groups
│   ├── routing/          # Route tables для NAT
│   ├── edge/             # Edge/NAT VM с Traefik + Xray
│   └── team_vm/          # VM для команд
├── templates/
│   ├── cloud-init/       # Шаблоны инициализации VM
│   ├── traefik/          # Конфигурация Traefik
│   └── xray/             # Конфигурация Xray
├── environments/
│   └── dev/              # Development environment
├── secrets/              # Сгенерированные ключи (gitignored)
├── docs/                 # Документация
├── provider.tf
├── variables.tf
└── outputs.tf
```

## Конфигурация

### Основные переменные

| Переменная | Описание | По умолчанию |
|------------|----------|--------------|
| `folder_id` | Yandex Cloud folder ID | - |
| `zone` | Зона доступности | ru-central1-a |
| `network_name` | Имя VPC | ai-camp-network |
| `public_cidr` | CIDR публичной подсети | 10.0.1.0/24 |
| `private_cidr` | CIDR приватной подсети | 10.0.2.0/24 |
| `domain` | Базовый домен | camp.aitalenthub.ru |

### Добавление новой команды

В `terraform.tfvars`:

```hcl
teams = {
  "01" = {
    user        = "team01"
    public_keys = ["ssh-ed25519 AAAA..."]
  }
  "02" = {
    user        = "team02"
    public_keys = ["ssh-ed25519 AAAA..."]
  }
  # Добавить новую команду:
  "03" = {
    user        = "team03"
    public_keys = ["ssh-ed25519 AAAA..."]
  }
}
```

Применить изменения:

```bash
terraform apply
```

### Автоматическая генерация SSH ключей

```hcl
generate_ssh_keys = true
```

Ключи будут сохранены в `secrets/`:
- `team-01-key` - private key
- `team-01-key.pub` - public key

## Подключение к инфраструктуре

### SSH через jump-host

```bash
# Формат
ssh -J jump@<edge-public-ip> <team-user>@<team-private-ip>

# Пример
ssh -J jump@bastion.camp.aitalenthub.ru team01@10.0.2.10
```

### Проверка NAT

```bash
# На team VM
curl ifconfig.co
# Должен показать публичный IP edge VM
```

## DNS конфигурация

После применения terraform настройте DNS записи:

```
*.camp.aitalenthub.ru    A    <edge-public-ip>
bastion.camp.aitalenthub.ru    A    <edge-public-ip>
```

## Удаление инфраструктуры

```bash
cd iac/environments/dev
terraform destroy
```

**Внимание:** Это удалит все ресурсы включая данные на VM!

## Troubleshooting

### Terraform не может подключиться к Yandex Cloud

```bash
# Проверить токен
echo $YC_TOKEN

# Или проверить service account key
echo $YC_SERVICE_ACCOUNT_KEY_FILE

# Обновить токен
export YC_TOKEN=$(yc iam create-token)
```

### VM не имеет доступа в интернет

1. Проверить route table привязан к private subnet
2. Проверить NAT на edge VM:
   ```bash
   # На edge VM
   sudo iptables -t nat -L -n -v
   ```

### SSH connection refused

1. Проверить security groups
2. Проверить SSH ключи
3. Проверить AllowTcpForwarding на edge

### Подробнее см. [docs/usage.md](docs/usage.md)

## Документация

- [Документация модулей](docs/modules.md)
- [Руководство пользователя](docs/usage.md)

## Поддержка

При возникновении проблем:
1. Проверьте [Troubleshooting](#troubleshooting)
2. Просмотрите логи: `terraform apply` с `-debug`
3. Создайте issue в репозитории
