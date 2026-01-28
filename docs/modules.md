# Документация модулей AI Camp Infrastructure

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

- Docker + Docker Compose
- Traefik (reverse proxy с TLS passthrough)
- Xray (transparent proxy через TPROXY для AI API)
- NAT (iptables masquerade)
- TPROXY (iptables mangle + policy routing)

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

## Диаграмма зависимостей

```
network ──┬──> security ──┬──> edge ──> routing
          │               │              │
          │               └──────────────┼──> team_vm
          │                              │
          └──────────────────────────────┘
```

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
