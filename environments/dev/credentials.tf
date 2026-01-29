# =============================================================================
# Team Credentials Management
# =============================================================================
# This file handles saving team SSH keys to files and generating credentials
# documentation. Keys are generated in main.tf to avoid circular dependencies.
# Separated from main infrastructure to allow independent updates.
# =============================================================================

module "team_credentials" {
  source = "../../modules/team-credentials"

  teams = {
    for team_id, team_config in var.teams :
    team_id => {
      user       = team_config.user
      private_ip = module.team_vm[team_id].private_ip
    }
  }

  domain     = var.domain
  jump_user  = var.jump_user
  bastion_ip = module.edge.edge_public_ip

  # Pass pre-generated SSH keys
  team_jump_private_keys   = { for k, v in tls_private_key.team_jump_key : k => v.private_key_openssh }
  team_jump_public_keys    = { for k, v in tls_private_key.team_jump_key : k => v.public_key_openssh }
  team_vm_private_keys     = { for k, v in tls_private_key.team_vm_key : k => v.private_key_openssh }
  team_vm_public_keys      = { for k, v in tls_private_key.team_vm_key : k => v.public_key_openssh }
  team_github_private_keys = { for k, v in tls_private_key.team_github_key : k => v.private_key_openssh }
  team_github_public_keys  = { for k, v in tls_private_key.team_github_key : k => v.public_key_openssh }

  depends_on = [module.edge, module.team_vm]
}
