# =============================================================================
# Configuration Synchronization
# =============================================================================
# This file handles synchronization of configuration files to servers.
# Separated from main infrastructure to allow config updates without VM changes.
# =============================================================================

module "config_sync" {
  source = "../../modules/config-sync"

  edge_public_ip        = module.edge.edge_public_ip
  jump_user             = var.jump_user
  jump_private_key_path = var.jump_private_key_path

  teams = {
    for team_id, team_config in var.teams :
    team_id => {
      user       = team_config.user
      private_ip = module.team_vm[team_id].private_ip
    }
  }

  team_jump_keys = {
    for team_id, team_config in var.teams :
    team_id => {
      public_key = tls_private_key.team_jump_key[team_id].public_key_openssh
      vm_ip      = module.team_vm[team_id].private_ip
    }
  }

  domain      = var.domain
  xray_config = local.xray_config

  enable_traefik_sync = true

  depends_on = [module.edge, module.team_vm, module.team_credentials]
}
