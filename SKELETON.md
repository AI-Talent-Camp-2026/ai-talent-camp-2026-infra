Вот **skeleton Terraform-проекта** для твоей архитектуры в Yandex Cloud — с модулями для сети, NAT/edge сервера, маршрутизации, security groups и team-VM. Он ориентирован на **ручной запуск** (без CI/CD), с использованием cloud-init и хранением секретов (SSH-ключей) где удобно

Ниже — структура проекта + примерные файлы, которые можно взять за основу и развивать под твою задачу.

---

## 📦 Структура репозитория

```
ai-talent-camp-2026-infra/
├── modules/
│   ├── network/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── security/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── routing/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── edge/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── team_vm/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf
│   └── prod/    (опционально)
│       ├── main.tf
│       ├── terraform.tfvars
│       └── backend.tf
├── variables.tf
├── outputs.tf
└── provider.tf
```

---

## 🧠 provider.tf

```hcl
terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.72.0"
    }
  }
}

provider "yandex" {
  folder_id = var.folder_id
  zone      = var.zone
}
```

---

## 📌 modules/network

### main.tf

```hcl
resource "yandex_vpc_network" "this" {
  name = var.network_name
}

resource "yandex_vpc_subnet" "public" {
  name           = "${var.network_name}-public"
  zone           = var.zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [var.public_cidr]
}

resource "yandex_vpc_subnet" "private" {
  name           = "${var.network_name}-private"
  zone           = var.zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [var.private_cidr]
}
```

### variables.tf

```hcl
variable "network_name" {}
variable "public_cidr" {}
variable "private_cidr" {}
variable "zone" {}
```

### outputs.tf

```hcl
output "network_id"     { value = yandex_vpc_network.this.id }
output "public_subnet"  { value = yandex_vpc_subnet.public.id }
output "private_subnet" { value = yandex_vpc_subnet.private.id }
```

---

## 📌 modules/security

### main.tf

```hcl
resource "yandex_vpc_security_group" "edge" {
  name       = "${var.name}-edge-sg"
  network_id = var.network_id

  ingress {
    protocol          = "tcp"
    v4_cidr_blocks    = ["0.0.0.0/0"]
    port              = 22
    description       = "SSH"
  }
  ingress {
    protocol          = "tcp"
    v4_cidr_blocks    = ["0.0.0.0/0"]
    port              = 80
    description       = "HTTP"
  }
  ingress {
    protocol          = "tcp"
    v4_cidr_blocks    = ["0.0.0.0/0"]
    port              = 443
    description       = "HTTPS"
  }

  egress {
    protocol          = "any"
    v4_cidr_blocks    = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "team" {
  name       = "${var.name}-team-sg"
  network_id = var.network_id

  ingress {
    protocol       = "tcp"
    security_group_ids = [yandex_vpc_security_group.edge.id]
    port           = 22
    description    = "SSH from edge"
  }
  ingress {
    protocol       = "tcp"
    security_group_ids = [yandex_vpc_security_group.edge.id]
    port_range     = "80-443"
    description    = "Web from edge"
  }

  egress {
    protocol       = "any"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### variables.tf

```hcl
variable "network_id" {}
variable "name" {}
```

### outputs.tf

```hcl
output "edge_sg" { value = yandex_vpc_security_group.edge.id }
output "team_sg" { value = yandex_vpc_security_group.team.id }
```

---

## 📌 modules/routing

Static route for private subnet via NAT instance:

### main.tf

```hcl
resource "yandex_vpc_route_table" "nat_route" {
  name       = "${var.name}-route"
  network_id = var.network_id

  static_route {
    destination_prefix = "0.0.0.0/0"
    next_hop_address   = var.nat_private_ip
  }
}

resource "yandex_vpc_subnet" "private_rt" {
  # повесить route table на private subnet
  subnet_id      = var.private_subnet
  route_table_id = yandex_vpc_route_table.nat_route.id
}
```

### variables.tf

```hcl
variable "name" {}
variable "network_id" {}
variable "nat_private_ip" {}
variable "private_subnet" {}
```

### outputs.tf

```hcl
output "route_table_id" { value = yandex_vpc_route_table.nat_route.id }
```

> Образец статического роутинга NAT-трафика есть в документации Terraform по NAT-инстансу. ([yandex.cloud][1])

---

## 📌 modules/edge

Edge/NAT VM with Traefik + Xray base:

### main.tf

```hcl
resource "yandex_compute_instance" "edge" {
  name        = "${var.name}-edge"
  zone        = var.zone
  platform_id = var.platform

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }

  network_interface {
    subnet_id = var.public_subnet
    nat       = true
    security_group_ids = [var.edge_sg]
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init.tpl", {
      traefik_config      = var.traefik_config
      xray_config         = var.xray_config
      jump_public_key     = var.jump_public_key
    })
  }
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}
```

### variables.tf

```hcl
variable "name" {}
variable "public_subnet" {}
variable "edge_sg" {}
variable "zone" {}
variable "platform" {}
variable "traefik_config" {}
variable "xray_config" {}
variable "jump_public_key" {}
```

### outputs.tf

```hcl
output "edge_public_ip"   { value = yandex_compute_instance.edge.network_interface[0].0.ip_address }
output "edge_private_ip"  { value = yandex_compute_instance.edge.network_interface[0].0.ip_address }
```

> Можно использовать готовые модули из GitHub terraform-yacloud-modules. ([GitHub][2])

---

## 📌 modules/team_vm

Team VM with cloud-init for SSH keys:

### main.tf

```hcl
resource "yandex_compute_instance" "team" {
  name        = "${var.name}-team-${var.index}"
  zone        = var.zone
  platform_id = var.platform

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }

  network_interface {
    subnet_id = var.private_subnet
    security_group_ids = [var.team_sg]
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init-team.tpl", {
      team_user     = var.team_user
      public_keys    = var.public_keys
    })
  }
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}
```

### variables.tf

```hcl
variable "name" {}
variable "zone" {}
variable "private_subnet" {}
variable "team_sg" {}
variable "platform" {}
variable "index" {}
variable "team_user" {}
variable "public_keys" { type = list(string) }
```

### outputs.tf

```hcl
output "team_vm_private_ip" { value = yandex_compute_instance.team.network_interface[0].0.ip_address }
```

---

## 🌍 environments/dev/main.tf

Это связывает модули вместе:

```hcl
module "network" {
  source        = "../../modules/network"
  network_name  = var.network_name
  public_cidr   = var.public_cidr
  private_cidr  = var.private_cidr
  zone          = var.zone
}

module "security" {
  source     = "../../modules/security"
  network_id = module.network.network_id
  name       = var.project
}

module "edge" {
  source        = "../../modules/edge"
  name          = var.project
  public_subnet = module.network.public_subnet
  edge_sg       = module.security.edge_sg
  zone          = var.zone
  platform      = var.edge_platform
  traefik_config = file(var.traefik_template)
  xray_config    = file(var.xray_template)
  jump_public_key = var.jump_public_key
}

module "routing" {
  source         = "../../modules/routing"
  name           = var.project
  network_id     = module.network.network_id
  nat_private_ip = module.edge.edge_private_ip
  private_subnet = module.network.private_subnet
}

module "team" {
  source         = "../../modules/team_vm"
  for_each       = var.teams
  name           = var.project
  zone           = var.zone
  private_subnet = module.network.private_subnet
  team_sg        = module.security.team_sg
  platform       = var.team_platform
  index          = each.key
  team_user      = each.value.user
  public_keys    = each.value.public_keys
}
```

---

## 📝 variables.tf

```hcl
variable "folder_id" {}
variable "network_name" {}
variable "public_cidr" {}
variable "private_cidr" {}
variable "project" {}
variable "zone" {}
variable "edge_platform" { default = "standard-v2" }
variable "team_platform" { default = "standard-v1" }
variable "jump_public_key" {}
variable "traefik_template" {}
variable "xray_template" {}
variable "teams" {
  type = map(object({
    user        = string
    public_keys = list(string)
  }))
}
```

---

## 📤 outputs.tf

```hcl
output "edge_public_ip" { value = module.edge.edge_public_ip }
output "team_ips"        { value = { for k,v in module.team : k => v.team_vm_private_ip } }
```

---

## 📄 backend.tf (опционально)

Если нужен хранить state в Object Storage:

```hcl
terraform {
  backend "s3" {
    bucket = "terraform-states"
    key    = "ai-camp/terraform.tfstate"
    endpoint = "https://storage.yandexcloud.net"
    region   = var.zone
  }
}
```

---

## 🧾 Примеры cloud-init шаблонов

### cloud-init.tpl (edge)

```yaml
#cloud-config
write_files:
  - path: /etc/traefik/traefik.yml
    content: ${traefik_config}
  - path: /etc/xray/config.json
    content: ${xray_config}

users:
  - name: jump
    ssh_authorized_keys:
      - ${jump_public_key}
    sudo: ALL=(ALL) NOPASSWD:ALL
```

### cloud-init-team.tpl

```yaml
#cloud-config
users:
  - name: ${team_user}
    ssh_authorized_keys:
%{ for key in public_keys ~}
      - ${key}
%{ endfor ~}
    sudo: ALL=(ALL) NOPASSWD:ALL
```

---

## 📌 Итог

✔ раздельные модули
✔ edge/NAT + routing через route table (private → edge) ([yandex.cloud][1])
✔ Traefik + Xray конфиги загружаются из шаблонов
✔ team-VM создаются по списку
✔ SSH ключи передаются через cloud-init


[1]: https://yandex.cloud/en/docs/tutorials/routing/nat-instance/terraform?utm_source=chatgpt.com "Routing through a NAT instance using Terraform"
[2]: https://github.com/terraform-yacloud-modules/terraform-yandex-vpc?utm_source=chatgpt.com "Terraform module to manage VPC resources within the Yandex.Cloud."
