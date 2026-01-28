# Документация модулей AI Camp Infrastructure

## Обзор

Инфраструктура состоит из следующих Terraform модулей:

```
modules/
├── network/     # VPC и подсети
├── security/    # Security groups
├── routing/     # Route tables для NAT
├── edge/        # Edge/NAT VM
└── team_vm/     # VM для команд
```

---

## Module: network

### Назначение

Создает VPC сеть с публичной и приватной подсетями.

### Ресурсы

- `yandex_vpc_network` - основная VPC
- `yandex_vpc_subnet.public` - публичная подсеть для edge VM
- `yandex_vpc_subnet.private` - приватная подсеть для team VMs

### Входные переменные

| Переменная | Тип | Описание | По умолчанию |
|------------|-----|----------|--------------|
| `network_name` | string | Имя VPC | - |
| `zone` | string | Зона доступности | - |
| `public_cidr` | string | CIDR публичной подсети | - |
| `private_cidr` | string | CIDR приватной подсети | - |
| `route_table_id` | string | ID route table для приватной подсети | null |

### Outputs

| Output | Описание |
|--------|----------|
| `network_id` | ID VPC |
| `public_subnet_id` | ID публичной подсети |
| `private_subnet_id` | ID приватной подсети |
| `public_subnet_cidr` | CIDR публичной подсети |
| `private_subnet_cidr` | CIDR приватной подсети |

### Пример использования

```hcl
module "network" {
  source = "../../modules/network"

  network_name = "ai-camp-network"
  zone         = "ru-central1-a"
  public_cidr  = "10.0.1.0/24"
  private_cidr = "10.0.2.0/24"
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

Создает edge/NAT VM с Traefik и Xray.

### Ресурсы

- `yandex_compute_instance.edge` - VM instance

### Компоненты (устанавливаются через cloud-init)

- Docker
- Traefik (reverse proxy с TLS passthrough)
- Xray (transparent proxy для AI API)
- NAT (iptables masquerade)

### Входные переменные

| Переменная | Тип | Описание | По умолчанию |
|------------|-----|----------|--------------|
| `name` | string | Базовое имя | - |
| `zone` | string | Зона доступности | - |
| `platform` | string | Platform ID | standard-v3 |
| `cores` | number | CPU cores | 2 |
| `memory` | number | RAM (GB) | 4 |
| `disk_size` | number | Disk (GB) | 30 |
| `preemptible` | bool | Прерываемая VM | false |
| `public_subnet_id` | string | ID публичной подсети | - |
| `edge_sg_id` | string | ID edge SG | - |
| `private_subnet_cidr` | string | CIDR приватной подсети | - |
| `jump_user` | string | Username для SSH | jump |
| `jump_public_key` | string | SSH public key | - |
| `traefik_config` | string | Конфиг Traefik | - |
| `xray_config` | string | Конфиг Xray | - |

### Outputs

| Output | Описание |
|--------|----------|
| `edge_public_ip` | Публичный IP |
| `edge_private_ip` | Приватный IP |
| `edge_instance_id` | Instance ID |
| `edge_fqdn` | FQDN |

---

## Module: team_vm

### Назначение

Создает VM для команды в приватной подсети.

### Ресурсы

- `yandex_compute_instance.team` - VM instance

### Компоненты (устанавливаются через cloud-init)

- Docker

### Входные переменные

| Переменная | Тип | Описание | По умолчанию |
|------------|-----|----------|--------------|
| `name` | string | Базовое имя | - |
| `team_id` | string | ID команды | - |
| `zone` | string | Зона доступности | - |
| `platform` | string | Platform ID | standard-v3 |
| `cores` | number | CPU cores | 2 |
| `memory` | number | RAM (GB) | 4 |
| `disk_size` | number | Disk (GB) | 30 |
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

---

## Диаграмма зависимостей

```
network ──┬──> security ──┬──> edge ──> routing
          │               │              │
          │               └──────────────┼──> team_vm
          │                              │
          └──────────────────────────────┘
```
