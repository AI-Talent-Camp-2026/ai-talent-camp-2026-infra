# =============================================================================
# AI Talent Camp Infrastructure - Development Environment
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
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
  }
}

# =============================================================================
# Provider Configuration
# =============================================================================

provider "yandex" {
  folder_id                = var.folder_id
  zone                     = var.zone
  service_account_key_file = "${path.module}/../../secrets/key.json"
}

# =============================================================================
# SSH Keys Generation for Teams
# =============================================================================
# Keys are generated early to break circular dependency with edge VM

# Jump keys (for bastion access) - unique per team
resource "tls_private_key" "team_jump_key" {
  for_each  = var.teams
  algorithm = "ED25519"
}

# VM keys (for team VM access)
resource "tls_private_key" "team_vm_key" {
  for_each  = var.teams
  algorithm = "ED25519"
}

# GitHub deploy keys (for CI/CD)
resource "tls_private_key" "team_github_key" {
  for_each  = var.teams
  algorithm = "ED25519"
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  # Generate Traefik config from template
  traefik_config = file("${path.module}/../../templates/traefik/traefik.yml")

  # Xray config: Use secrets/xray-config.json if exists, otherwise generate from template
  xray_config_file = "${path.module}/../../secrets/xray-config.json"
  xray_config = fileexists(local.xray_config_file) ? file(local.xray_config_file) : templatefile("${path.module}/../../templates/xray/config.json.tpl", {
    vless_server      = var.vless_server
    vless_server_ip   = var.vless_server_ip
    vless_port        = var.vless_port
    vless_uuid        = var.vless_uuid
    vless_sni         = var.vless_sni
    vless_fingerprint = var.vless_fingerprint
    vless_public_key  = var.vless_public_key
    vless_short_id    = var.vless_short_id
  })
}

# =============================================================================
# Create Initial Xray Config (if doesn't exist)
# =============================================================================

resource "local_file" "xray_config_initial" {
  count = fileexists(local.xray_config_file) ? 0 : 1

  filename = local.xray_config_file
  content = templatefile("${path.module}/../../templates/xray/config.json.tpl", {
    vless_server      = var.vless_server
    vless_server_ip   = var.vless_server_ip
    vless_port        = var.vless_port
    vless_uuid        = var.vless_uuid
    vless_sni         = var.vless_sni
    vless_fingerprint = var.vless_fingerprint
    vless_public_key  = var.vless_public_key
    vless_short_id    = var.vless_short_id
  })

  lifecycle {
    ignore_changes = [content]
  }
}

# =============================================================================
# Module: Network (VPC and public subnet only)
# =============================================================================

module "network_base" {
  source = "../../modules/network"

  network_name          = var.network_name
  zone                  = var.zone
  public_cidr           = var.public_cidr
  private_cidr          = var.private_cidr
  create_private_subnet = false # Created separately with route table
  route_table_id        = null
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
# Module: Edge VM (NAT Gateway + Jump Host)
# =============================================================================

module "edge" {
  source = "../../modules/edge"

  name                = var.project_name
  zone                = var.zone
  platform            = var.edge_platform
  cores               = var.edge_cores
  memory              = var.edge_memory
  disk_size           = var.edge_disk_size
  core_fraction       = var.edge_core_fraction
  preemptible         = var.edge_preemptible
  public_subnet_id    = module.network_base.public_subnet_id
  edge_sg_id          = module.security.edge_sg_id
  private_subnet_cidr = var.private_cidr
  jump_user           = var.jump_user
  jump_public_key     = var.jump_public_key
  vless_server_ip     = var.vless_server_ip
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

resource "yandex_vpc_subnet" "private_with_nat" {
  name           = "${var.network_name}-private"
  description    = "Private subnet for team VMs with NAT routing"
  zone           = var.zone
  network_id     = module.network_base.network_id
  v4_cidr_blocks = [var.private_cidr]
  route_table_id = module.routing.route_table_id

  depends_on = [module.routing]
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
  core_fraction     = var.team_core_fraction
  preemptible       = var.team_preemptible
  private_subnet_id = yandex_vpc_subnet.private_with_nat.id
  team_sg_id        = module.security.team_sg_id
  team_user         = each.value.user
  # Use generated VM key, plus any additional keys from config
  public_keys = concat(
    [tls_private_key.team_vm_key[each.key].public_key_openssh],
    each.value.public_keys
  )
  domain = var.domain

  depends_on = [yandex_vpc_subnet.private_with_nat]
}
