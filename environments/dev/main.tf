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

  # Collect all team jump public keys for bastion authorized_keys
  team_jump_public_keys = [for key in tls_private_key.team_jump_key : key.public_key_openssh]
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
  create_private_subnet = false  # Created separately with route table
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
  team_jump_keys      = local.team_jump_public_keys
  vless_server_ip     = var.vless_server_ip
  traefik_config      = local.traefik_config
  xray_config         = local.xray_config
}

# =============================================================================
# Sync Team Jump Keys to Bastion
# =============================================================================

resource "null_resource" "sync_team_jump_key_to_bastion" {
  for_each = var.teams

  triggers = {
    jump_key_fingerprint = md5(tls_private_key.team_jump_key[each.key].public_key_openssh)
    bastion_ip           = module.edge.edge_public_ip
  }

  connection {
    type        = "ssh"
    user        = var.jump_user
    private_key = file(pathexpand(var.jump_private_key_path))
    host        = module.edge.edge_public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "grep -qF '${trimspace(tls_private_key.team_jump_key[each.key].public_key_openssh)}' ~/.ssh/authorized_keys || echo '${trimspace(tls_private_key.team_jump_key[each.key].public_key_openssh)}' >> ~/.ssh/authorized_keys"
    ]
  }

  depends_on = [module.edge]
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
  public_keys       = concat(
    [tls_private_key.team_vm_key[each.key].public_key_openssh],
    each.value.public_keys
  )
  domain            = var.domain

  depends_on = [yandex_vpc_subnet.private_with_nat]
}

# =============================================================================
# Generate Traefik Dynamic Configuration
# =============================================================================

# Auto-generated routes for team VMs (always regenerated by Terraform)
resource "local_file" "traefik_dynamic_auto" {
  count = length(var.teams) > 0 ? 1 : 0

  filename = "${path.module}/../../secrets/traefik-dynamic-auto.yml"
  content = templatefile("${path.module}/../../templates/traefik/dynamic.yml.tpl", {
    teams  = { for team_id, team in module.team_vm : team_id => { private_ip = team.private_ip } }
    domain = var.domain
  })

  depends_on = [module.team_vm]
}

# Custom routes file (created once, then ignored by Terraform)
resource "local_file" "traefik_dynamic_custom" {
  count = length(var.teams) > 0 ? 1 : 0

  filename = "${path.module}/../../secrets/traefik-dynamic-custom.yml"
  content  = <<-EOT
    # =============================================================================
    # Traefik Custom Configuration
    # =============================================================================
    # This file is for your custom routes and configurations.
    # Terraform will NOT overwrite this file after initial creation.
    # Add your custom HTTP/TCP routers, services, and middlewares here.
    # =============================================================================

    # Example custom HTTP router:
    # http:
    #   routers:
    #     my-custom-service:
    #       entryPoints:
    #         - web
    #       rule: "Host(`custom.${var.domain}`)"
    #       service: my-custom-service
    #
    #   services:
    #     my-custom-service:
    #       loadBalancer:
    #         servers:
    #           - url: "http://10.20.0.10:8080"
  EOT

  lifecycle {
    ignore_changes = [content]
  }
}

# =============================================================================
# Create Initial Xray Config (if doesn't exist)
# =============================================================================
# On first run, generate secrets/xray-config.json from template.
# After that, you can edit this file directly and changes will be synced.

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
# Sync Xray Configuration to Edge VM
# =============================================================================
# This allows updating Xray config without recreating the edge VM.
# Edit secrets/xray-config.json and run terraform apply to sync changes.

resource "null_resource" "sync_xray_config" {
  triggers = {
    xray_config_hash = md5(local.xray_config)
    edge_ip          = module.edge.edge_public_ip
  }

  connection {
    type        = "ssh"
    user        = var.jump_user
    private_key = file(pathexpand(var.jump_private_key_path))
    host        = module.edge.edge_public_ip
  }

  provisioner "file" {
    content     = local.xray_config
    destination = "/tmp/xray-config.json"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/xray-config.json /opt/xray/config.json",
      "sudo systemctl restart xray",
      "echo 'Xray config updated and service restarted'"
    ]
  }

  depends_on = [module.edge]
}

# =============================================================================
# Sync Traefik Dynamic Configuration to Edge VM
# =============================================================================
# This allows updating Traefik dynamic config without recreating the edge VM.
# Changes to team VMs will automatically update traefik-dynamic-auto.yml and sync.

resource "null_resource" "sync_traefik_dynamic_auto" {
  count = length(var.teams) > 0 ? 1 : 0

  triggers = {
    traefik_auto_config_hash = md5(local_file.traefik_dynamic_auto[0].content)
    edge_ip                  = module.edge.edge_public_ip
  }

  connection {
    type        = "ssh"
    user        = var.jump_user
    private_key = file(pathexpand(var.jump_private_key_path))
    host        = module.edge.edge_public_ip
  }

  provisioner "file" {
    content     = local_file.traefik_dynamic_auto[0].content
    destination = "/tmp/traefik-dynamic-auto.yml"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/traefik-dynamic-auto.yml /opt/traefik/dynamic/auto.yml",
      "sudo chmod 644 /opt/traefik/dynamic/auto.yml",
      "echo 'Traefik auto-generated config updated (will be reloaded automatically)'"
    ]
  }

  depends_on = [module.edge, local_file.traefik_dynamic_auto]
}

# Sync custom Traefik config (only if doesn't exist on server)
resource "null_resource" "sync_traefik_dynamic_custom" {
  count = length(var.teams) > 0 ? 1 : 0

  triggers = {
    edge_ip = module.edge.edge_public_ip
  }

  connection {
    type        = "ssh"
    user        = var.jump_user
    private_key = file(pathexpand(var.jump_private_key_path))
    host        = module.edge.edge_public_ip
  }

  provisioner "file" {
    content     = local_file.traefik_dynamic_custom[0].content
    destination = "/tmp/traefik-dynamic-custom.yml"
  }

  provisioner "remote-exec" {
    inline = [
      "if [ ! -f /opt/traefik/dynamic/custom.yml ]; then",
      "  sudo mv /tmp/traefik-dynamic-custom.yml /opt/traefik/dynamic/custom.yml",
      "  sudo chmod 644 /opt/traefik/dynamic/custom.yml",
      "  echo 'Traefik custom config created'",
      "else",
      "  rm /tmp/traefik-dynamic-custom.yml",
      "  echo 'Traefik custom config already exists, skipping'",
      "fi"
    ]
  }

  depends_on = [module.edge, local_file.traefik_dynamic_custom]
}

# =============================================================================
# Team Credentials - Directory Structure
# =============================================================================

# Create team directories
resource "local_file" "team_dir_marker" {
  for_each = var.teams

  filename = "${path.module}/../../secrets/team-${each.key}/.gitkeep"
  content  = ""
}

# =============================================================================
# Team Credentials - Jump Keys (for bastion access)
# =============================================================================

resource "local_file" "team_jump_private_key" {
  for_each = var.teams

  filename        = "${path.module}/../../secrets/team-${each.key}/${each.value.user}-jump-key"
  content         = tls_private_key.team_jump_key[each.key].private_key_openssh
  file_permission = "0600"
}

resource "local_file" "team_jump_public_key" {
  for_each = var.teams

  filename = "${path.module}/../../secrets/team-${each.key}/${each.value.user}-jump-key.pub"
  content  = tls_private_key.team_jump_key[each.key].public_key_openssh
}

# =============================================================================
# Team Credentials - VM Keys (for team VM access)
# =============================================================================

resource "local_file" "team_vm_private_key" {
  for_each = var.teams

  filename        = "${path.module}/../../secrets/team-${each.key}/${each.value.user}-key"
  content         = tls_private_key.team_vm_key[each.key].private_key_openssh
  file_permission = "0600"
}

resource "local_file" "team_vm_public_key" {
  for_each = var.teams

  filename = "${path.module}/../../secrets/team-${each.key}/${each.value.user}-key.pub"
  content  = tls_private_key.team_vm_key[each.key].public_key_openssh
}

# =============================================================================
# Team Credentials - GitHub Deploy Keys
# =============================================================================

resource "local_file" "team_github_private_key" {
  for_each = var.teams

  filename        = "${path.module}/../../secrets/team-${each.key}/${each.value.user}-deploy-key"
  content         = tls_private_key.team_github_key[each.key].private_key_openssh
  file_permission = "0600"
}

resource "local_file" "team_github_public_key" {
  for_each = var.teams

  filename = "${path.module}/../../secrets/team-${each.key}/${each.value.user}-deploy-key.pub"
  content  = tls_private_key.team_github_key[each.key].public_key_openssh
}

# =============================================================================
# Team Credentials - SSH Config
# =============================================================================

resource "local_file" "team_ssh_config" {
  for_each = var.teams

  filename = "${path.module}/../../secrets/team-${each.key}/ssh-config"
  content  = <<-EOT
# =============================================================================
# AI Camp SSH Config for ${each.value.user}
# =============================================================================
# Usage:
#   1. Copy this folder to ~/.ssh/ai-camp/
#   2. chmod 600 ~/.ssh/ai-camp/*-key
#   3. ssh -F ~/.ssh/ai-camp/ssh-config ${each.value.user}
# Alternatively, you can copy content of this file into your ~/.ssh/config
# And use it as a regular SSH config.
#   - ssh ${each.value.user}
# =============================================================================

Host bastion
  HostName bastion.${var.domain}
  User ${var.jump_user}
  IdentityFile ~/.ssh/ai-camp/${each.value.user}-jump-key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host ${each.value.user}
  HostName ${module.team_vm[each.key].private_ip}
  User ${each.value.user}
  ProxyJump bastion
  IdentityFile ~/.ssh/ai-camp/${each.value.user}-key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOT

  depends_on = [module.edge, module.team_vm]
}

# =============================================================================
# Team Credentials - Summary JSON
# =============================================================================

resource "local_file" "teams_credentials_json" {
  count = length(var.teams) > 0 ? 1 : 0

  filename = "${path.module}/../../secrets/teams-credentials.json"
  content = jsonencode({
    bastion = {
      host   = module.edge.edge_public_ip
      user   = var.jump_user
      domain = "bastion.${var.domain}"
    }
    teams = {
      for team_id, team_config in var.teams :
      team_id => {
        user        = team_config.user
        private_ip  = module.team_vm[team_id].private_ip
        domain      = "${team_config.user}.${var.domain}"
        ssh_command = "ssh -F ~/.ssh/ai-camp/ssh-config ${team_config.user}"
        folder      = "secrets/team-${team_id}/"
        files = {
          jump_key   = "${team_config.user}-jump-key"
          vm_key     = "${team_config.user}-key"
          github_key = "${team_config.user}-deploy-key"
          ssh_config = "ssh-config"
        }
      }
    }
    traefik = {
      auto_config   = "secrets/traefik-dynamic-auto.yml"
      custom_config = "secrets/traefik-dynamic-custom.yml"
      note          = "auto_config is regenerated by Terraform, custom_config is for manual additions"
    }
  })

  depends_on = [module.edge, module.team_vm]
}
