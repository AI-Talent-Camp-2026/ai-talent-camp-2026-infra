# =============================================================================
# AI Camp Infrastructure - Development Environment
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.72.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
  }
}

# =============================================================================
# Provider Configuration
# =============================================================================

provider "yandex" {
  folder_id = var.folder_id
  zone      = var.zone
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  # Generate Traefik config from template
  traefik_config = file("${path.module}/../../templates/traefik/traefik.yml")

  # Generate Xray config from template
  xray_config = templatefile("${path.module}/../../templates/xray/config.json.tpl", {
    vless_server  = var.vless_server
    vless_port    = var.vless_port
    vless_uuid    = var.vless_uuid
    proxy_domains = var.proxy_domains
  })
}

# =============================================================================
# Module: Routing (created first for route table)
# =============================================================================

# We need to create network first without route table,
# then edge VM, then routing, then update network with route table.
# This is a workaround for the circular dependency.

# Step 1: Create network without route table
module "network_base" {
  source = "../../modules/network"

  network_name   = var.network_name
  zone           = var.zone
  public_cidr    = var.public_cidr
  private_cidr   = var.private_cidr
  route_table_id = null
}

# =============================================================================
# Module: Security Groups
# =============================================================================

module "security" {
  source = "../../modules/security"

  name                = var.project_name
  network_id          = module.network_base.network_id
  private_subnet_cidr = var.private_cidr
}

# =============================================================================
# Module: Edge VM (NAT Gateway)
# =============================================================================

module "edge" {
  source = "../../modules/edge"

  name                = var.project_name
  zone                = var.zone
  platform            = var.edge_platform
  cores               = var.edge_cores
  memory              = var.edge_memory
  disk_size           = var.edge_disk_size
  preemptible         = var.edge_preemptible
  public_subnet_id    = module.network_base.public_subnet_id
  edge_sg_id          = module.security.edge_sg_id
  private_subnet_cidr = var.private_cidr
  jump_user           = var.jump_user
  jump_public_key     = var.jump_public_key
  traefik_config      = local.traefik_config
  xray_config         = local.xray_config
}

# =============================================================================
# Module: Routing
# =============================================================================

module "routing" {
  source = "../../modules/routing"

  name           = var.project_name
  network_id     = module.network_base.network_id
  nat_gateway_ip = module.edge.edge_private_ip
}

# =============================================================================
# Private Subnet with Route Table
# =============================================================================

# Create a separate private subnet with route table attached
# This replaces the one from network_base module
resource "yandex_vpc_subnet" "private_with_nat" {
  name           = "${var.network_name}-private"
  description    = "Private subnet for team VMs with NAT routing"
  zone           = var.zone
  network_id     = module.network_base.network_id
  v4_cidr_blocks = [var.private_cidr]
  route_table_id = module.routing.route_table_id

  # Ensure this is created after routing module
  depends_on = [module.routing]

  lifecycle {
    # Replace network_base.private subnet
    create_before_destroy = true
  }
}

# =============================================================================
# Module: Team VMs
# =============================================================================

module "team_vm" {
  source   = "../../modules/team_vm"
  for_each = var.teams

  name              = var.project_name
  team_id           = each.key
  zone              = var.zone
  platform          = var.team_platform
  cores             = var.team_cores
  memory            = var.team_memory
  disk_size         = var.team_disk_size
  preemptible       = var.team_preemptible
  private_subnet_id = yandex_vpc_subnet.private_with_nat.id
  team_sg_id        = module.security.team_sg_id
  team_user         = each.value.user
  public_keys       = each.value.public_keys
  domain            = var.domain

  depends_on = [yandex_vpc_subnet.private_with_nat]
}

# =============================================================================
# Generate Traefik Dynamic Configuration
# =============================================================================

resource "local_file" "traefik_dynamic" {
  count = length(var.teams) > 0 ? 1 : 0

  filename = "${path.module}/../../secrets/traefik-dynamic.yml"
  content = templatefile("${path.module}/../../templates/traefik/dynamic.yml.tpl", {
    teams  = { for team_id, team in module.team_vm : team_id => { private_ip = team.private_ip } }
    domain = var.domain
  })

  depends_on = [module.team_vm]
}

# =============================================================================
# SSH Keys Generation (Optional)
# =============================================================================

resource "tls_private_key" "team_keys" {
  for_each = var.generate_ssh_keys ? var.teams : {}

  algorithm = "ED25519"
}

resource "local_file" "team_private_keys" {
  for_each = var.generate_ssh_keys ? var.teams : {}

  filename        = "${path.module}/../../secrets/team-${each.key}-key"
  content         = tls_private_key.team_keys[each.key].private_key_openssh
  file_permission = "0600"
}

resource "local_file" "team_public_keys" {
  for_each = var.generate_ssh_keys ? var.teams : {}

  filename = "${path.module}/../../secrets/team-${each.key}-key.pub"
  content  = tls_private_key.team_keys[each.key].public_key_openssh
}
