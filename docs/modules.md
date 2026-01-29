# Документация модулей AI Talent Camp Infrastructure

> **Последнее обновление:** 2026-01-29  
> **Связанные документы:** [architecture.md](architecture.md), [admin-guide.md](admin-guide.md)

## Обзор

Инфраструктура состоит из следующих Terraform модулей:

```
modules/
├── network/     # VPC и подсети
├── security/    # Security groups
├── routing/     # Route tables для NAT
├── edge/        # Edge/NAT VM с Traefik + Xray + TPROXY
└── team_vm/     # VM для команд
```

---

## Module: network

### Назначение

Создает VPC сеть с публичной подсетью. Приватная подсеть создаётся отдельно с route table.

### Ресурсы

- `yandex_vpc_network` - основная VPC
- `yandex_vpc_subnet.public` - публичная подсеть для edge VM
- `yandex_vpc_subnet.private` - приватная подсеть (опционально, если `create_private_subnet = true`)

### Входные переменные

| Переменная | Тип | Описание | По умолчанию |
|------------|-----|----------|--------------|
| `network_name` | string | Имя VPC | - |
| `zone` | string | Зона доступности | - |
| `public_cidr` | string | CIDR публичной подсети | - |
| `private_cidr` | string | CIDR приватной подсети | - |
| `route_table_id` | string | ID route table для приватной подсети | null |
| `create_private_subnet` | bool | Создавать приватную подсеть | true |

**Примечание:** В `environments/dev/main.tf` приватная подсеть создаётся отдельно с route table, поэтому `create_private_subnet = false` передаётся в модуль.

### Outputs

| Output | Описание |
|--------|----------|
| `network_id` | ID VPC |
| `public_subnet_id` | ID публичной подсети |
| `private_subnet_id` | ID приватной подсети (null если не создана) |
| `public_subnet_cidr` | CIDR публичной подсети |
| `private_subnet_cidr` | CIDR приватной подсети |

### Пример использования

```hcl
module "network" {
  source = "../../modules/network"

  network_name          = "ai-camp-network"
  zone                  = "ru-central1-a"
  public_cidr           = "10.0.1.0/24"
  private_cidr          = "10.0.2.0/24"
  create_private_subnet = false  # Создаётся отдельно с route table
  route_table_id        = null
}
```

---

## Module: security

### Назначение

Создает security groups для edge и team VMs.

### Ресурсы

- `yandex_vpc_security_group.edge` - SG для edge VM
- `yandex_vpc_security_group.team` - SG для team VMs

### Правила Edge SG

| Направление | Протокол | Порт | Источник |
|-------------|----------|------|----------|
| Ingress | TCP | 22 | 0.0.0.0/0 |
| Ingress | TCP | 80 | 0.0.0.0/0 |
| Ingress | TCP | 443 | 0.0.0.0/0 |
| Ingress | ANY | - | private_subnet_cidr |
| Ingress | ICMP | - | 0.0.0.0/0 |
| Egress | ANY | - | 0.0.0.0/0 |

### Правила Team SG

| Направление | Протокол | Порт | Источник |
|-------------|----------|------|----------|
| Ingress | TCP | 22 | Edge SG |
| Ingress | TCP | 80 | Edge SG |
| Ingress | TCP | 443 | Edge SG |
| Ingress | ANY | - | self_security_group |
| Ingress | ICMP | - | Edge SG |
| Egress | ANY | - | 0.0.0.0/0 |

### Входные переменные

| Переменная | Тип | Описание |
|------------|-----|----------|
| `name` | string | Базовое имя для ресурсов |
| `network_id` | string | ID VPC |
| `private_subnet_cidr` | string | CIDR приватной подсети |

### Outputs

| Output | Описание |
|--------|----------|
| `edge_sg_id` | ID edge security group |
| `team_sg_id` | ID team security group |

---

## Module: routing

### Назначение

Создает route table для маршрутизации трафика через NAT VM.

### Ресурсы

- `yandex_vpc_route_table.nat` - таблица маршрутизации

### Маршрут

| Destination | Next Hop |
|-------------|----------|
| 0.0.0.0/0 | Edge VM private IP |

### Входные переменные

| Переменная | Тип | Описание |
|------------|-----|----------|
| `name` | string | Базовое имя |
| `network_id` | string | ID VPC |
| `nat_gateway_ip` | string | Private IP edge VM |

### Outputs

| Output | Описание |
|--------|----------|
| `route_table_id` | ID route table |

---

## Module: edge

### Назначение

Создает edge/NAT VM с Traefik, Xray (TPROXY) и NAT.

### Ресурсы

- `yandex_compute_instance.edge` - VM instance

### Компоненты (устанавливаются через cloud-init)

- **Docker + Docker Compose** - контейнеризация для Traefik
- **Traefik** (Docker контейнер) - reverse proxy с TLS passthrough
- **Xray** (systemd сервис) - transparent proxy через TPROXY для AI API
- **NAT** (iptables masquerade) - маршрутизация исходящего трафика
- **TPROXY** (iptables mangle + policy routing) - прозрачное проксирование

**Важно:** Traefik работает как Docker контейнер, а Xray как нативный systemd сервис для поддержки TPROXY с `IP_TRANSPARENT` socket option.

### TPROXY настройки

TPROXY перехватывает весь трафик из private subnet и маршрутизирует через Xray:

- Policy routing: `ip rule add fwmark 1 table 100`
- iptables mangle chain XRAY для перехвата TCP/UDP
- Исключения: private networks (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16) и VLESS server IP
- TPROXY redirect на порт 12345 (Xray dokodemo-door)

### Входные переменные

| Переменная | Тип | Описание | По умолчанию |
|------------|-----|----------|--------------|
| `name` | string | Базовое имя | - |
| `zone` | string | Зона доступности | - |
| `platform` | string | Platform ID | standard-v3 |
| `cores` | number | CPU cores | 2 |
| `memory` | number | RAM (GB) | 4 |
| `disk_size` | number | Disk (GB) | 20 |
| `core_fraction` | number | Guaranteed vCPU share | 100 |
| `preemptible` | bool | Прерываемая VM | false |
| `public_subnet_id` | string | ID публичной подсети | - |
| `edge_sg_id` | string | ID edge SG | - |
| `private_subnet_cidr` | string | CIDR приватной подсети | - |
| `jump_user` | string | Username для SSH | jump |
| `jump_public_key` | string | SSH public key (админский) | - |
| `team_jump_keys` | list(string) | SSH public keys команд для bastion | [] |
| `vless_server_ip` | string | VLESS server IP (исключается из TPROXY) | "" |
| `traefik_config` | string | Конфиг Traefik | - |
| `xray_config` | string | Конфиг Xray | - |

### Outputs

| Output | Описание |
|--------|----------|
| `edge_public_ip` | Публичный IP |
| `edge_private_ip` | Приватный IP |
| `edge_instance_id` | Instance ID |
| `edge_fqdn` | FQDN |

### Пример использования

```hcl
module "edge" {
  source = "../../modules/edge"

  name                = "ai-camp"
  zone                = "ru-central1-a"
  cores               = 2
  memory              = 4
  disk_size           = 20
  core_fraction       = 100
  public_subnet_id    = module.network.public_subnet_id
  edge_sg_id          = module.security.edge_sg_id
  private_subnet_cidr = "10.0.2.0/24"
  jump_user           = "jump"
  jump_public_key     = var.jump_public_key
  team_jump_keys      = local.team_jump_public_keys
  vless_server_ip     = var.vless_server_ip
  traefik_config      = local.traefik_config
  xray_config         = local.xray_config
}
```

---

## Module: team_vm

### Назначение

Создает VM для команды в приватной подсети.

### Ресурсы

- `yandex_compute_instance.team` - VM instance

### Компоненты (устанавливаются через cloud-init)

- Минимальная конфигурация Ubuntu 22.04
- Пользователь с sudo правами
- Рабочая директория `/home/<user>/workspace`

**Команды устанавливают всё необходимое сами** (Docker, Nginx, языки программирования и т.д.)

### Входные переменные

| Переменная | Тип | Описание | По умолчанию |
|------------|-----|----------|--------------|
| `name` | string | Базовое имя | - |
| `team_id` | string | ID команды | - |
| `zone` | string | Зона доступности | - |
| `platform` | string | Platform ID | standard-v3 |
| `cores` | number | CPU cores | 4 |
| `memory` | number | RAM (GB) | 8 |
| `disk_size` | number | Disk (GB) | 65 |
| `core_fraction` | number | Guaranteed vCPU share | 100 |
| `preemptible` | bool | Прерываемая VM | false |
| `private_subnet_id` | string | ID приватной подсети | - |
| `team_sg_id` | string | ID team SG | - |
| `team_user` | string | Username | - |
| `public_keys` | list(string) | SSH public keys | - |
| `domain` | string | Базовый домен | camp.aitalenthub.ru |

### Outputs

| Output | Описание |
|--------|----------|
| `private_ip` | Приватный IP |
| `instance_id` | Instance ID |
| `fqdn` | FQDN |
| `hostname` | Hostname |

### Пример использования

```hcl
module "team_vm" {
  source = "../../modules/team_vm"

  name              = "ai-camp"
  team_id           = "01"
  zone              = "ru-central1-a"
  cores             = 4
  memory            = 8
  disk_size         = 65
  core_fraction     = 100
  private_subnet_id = yandex_vpc_subnet.private.id
  team_sg_id        = module.security.team_sg_id
  team_user         = "team01"
  public_keys       = ["ssh-ed25519 AAAA..."]
  domain            = "camp.aitalenthub.ru"
}
```

---

## Module: team-credentials

### Назначение

Управляет SSH ключами команд и генерирует credentials файлы.

### Ресурсы

- `local_file.team_jump_private_key` - приватный ключ для bastion
- `local_file.team_vm_private_key` - приватный ключ для VM
- `local_file.team_github_private_key` - приватный ключ для GitHub/CI
- `local_file.team_ssh_config` - готовый SSH конфиг
- `local_file.teams_credentials_json` - сводка всех команд в JSON

### Входные переменные

| Переменная | Тип | Описание |
|------------|-----|----------|
| `teams` | map(object) | Конфигурация команд |
| `bastion_host` | string | Hostname bastion сервера |
| `team_jump_private_keys` | map(string) | Приватные ключи для bastion |
| `team_vm_private_keys` | map(string) | Приватные ключи для VM |
| `team_github_private_keys` | map(string) | Приватные ключи для GitHub |

### Outputs

| Output | Описание |
|--------|----------|
| `credentials_folders` | Пути к папкам с credentials |

### Генерируемые файлы

Для каждой команды создаётся папка `secrets/team-XX/` с файлами:

```
secrets/team-01/
├── team01-jump-key          # Приватный ключ для bastion
├── team01-jump-key.pub      # Публичный ключ для bastion  
├── team01-key               # Приватный ключ для VM
├── team01-key.pub           # Публичный ключ для VM
├── team01-deploy-key        # Приватный ключ для GitHub
├── team01-deploy-key.pub    # Публичный ключ для GitHub
└── ssh-config               # Готовый SSH конфиг
```

### Пример использования

```hcl
module "team_credentials" {
  source = "../../modules/team-credentials"

  teams                     = var.teams
  bastion_host              = var.bastion_host
  team_jump_private_keys    = { for k, v in tls_private_key.team_jump_key : k => v.private_key_openssh }
  team_jump_public_keys     = { for k, v in tls_private_key.team_jump_key : k => v.public_key_openssh }
  team_vm_private_keys      = { for k, v in tls_private_key.team_vm_key : k => v.private_key_openssh }
  team_vm_public_keys       = { for k, v in tls_private_key.team_vm_key : k => v.public_key_openssh }
  team_github_private_keys  = { for k, v in tls_private_key.team_github_key : k => v.private_key_openssh }
  team_github_public_keys   = { for k, v in tls_private_key.team_github_key : k => v.public_key_openssh }
}
```

**Преимущества:**
- Изолированное управление credentials
- Независимые обновления без влияния на инфраструктуру
- Автоматическая генерация SSH конфигов

---

## Module: config-sync

### Назначение

Синхронизирует конфигурационные файлы на серверы.

### Ресурсы

- `local_file.traefik_dynamic_config` - динамическая конфигурация Traefik
- `null_resource.sync_xray_config` - синхронизация Xray конфига
- `null_resource.sync_traefik_configs` - синхронизация Traefik конфигов
- `null_resource.sync_team_jump_keys` - синхронизация jump ключей

### Входные переменные

| Переменная | Тип | Описание |
|------------|-----|----------|
| `edge_public_ip` | string | Публичный IP edge VM |
| `jump_private_key_path` | string | Путь к приватному ключу jump |
| `teams` | map(object) | Конфигурация команд |
| `xray_config_path` | string | Путь к xray-config.json |
| `traefik_config` | string | Содержимое traefik.yml |

### Outputs

Модуль не имеет outputs.

### Процесс синхронизации

1. **Xray конфигурация:**
   - Копирует `secrets/xray-config.json` на edge VM
   - Перезапускает Xray сервис
   - Проверяет статус после перезапуска

2. **Traefik конфигурация:**
   - Генерирует динамическую конфигурацию для teams
   - Копирует статическую и динамическую конфигурации
   - Traefik автоматически подхватывает изменения

3. **Jump ключи:**
   - Синхронизирует публичные ключи команд на bastion
   - Обновляет `~jump/.ssh/authorized_keys`

### Пример использования

```hcl
module "config_sync" {
  source = "../../modules/config-sync"

  edge_public_ip          = module.edge.edge_public_ip
  jump_private_key_path   = var.jump_private_key_path
  teams                   = var.teams
  xray_config_path        = local.xray_config_path
  traefik_config          = local.traefik_config
  
  depends_on = [
    module.edge,
    module.team_vm
  ]
}
```

**Преимущества:**
- Четкое разделение: создание инфраструктуры vs обновление конфигов
- Можно обновлять конфиги без изменения VM
- Легче отлаживать проблемы синхронизации
- Автоматический перезапуск сервисов после изменений

---

## Диаграмма зависимостей

```
network ──┬──> security ──┬──> edge ──> routing
          │               │              │
          │               └──────────────┼──> team_vm
          │                              │
          └──────────────────────────────┘
                                         │
                                         ├──> team-credentials
                                         │
                                         └──> config-sync
```

**Важно:** Модули `team-credentials` и `config-sync` не создают cloud ресурсы, они управляют только локальными файлами и синхронизацией.

## Порядок создания ресурсов

1. **network** - создаёт VPC и публичную подсеть
2. **security** - создаёт security groups
3. **edge** - создаёт edge VM (зависит от network и security)
4. **routing** - создаёт route table (зависит от network и edge)
5. **private subnet** - создаётся отдельно с route table (зависит от routing)
6. **team_vm** - создаёт VM команд (зависит от private subnet и security)

## Генерация ключей (в environments/dev/main.tf)

Для каждой команды автоматически генерируются:

- `tls_private_key.team_jump_key` - ключ для bastion
- `tls_private_key.team_vm_key` - ключ для VM команды
- `tls_private_key.team_github_key` - ключ для GitHub CI/CD

Все ключи сохраняются в `secrets/team-XX/` вместе с готовым SSH config.
