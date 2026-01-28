# =============================================================================
# Network Outputs
# =============================================================================

output "network_id" {
  description = "ID of the created VPC network"
  value       = module.network_base.network_id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = module.network_base.public_subnet_id
}

output "private_subnet_id" {
  description = "ID of the private subnet with NAT routing"
  value       = yandex_vpc_subnet.private_with_nat.id
}

# =============================================================================
# Edge VM Outputs
# =============================================================================

output "edge_public_ip" {
  description = "Public IP address of the edge/NAT VM"
  value       = module.edge.edge_public_ip
}

output "edge_private_ip" {
  description = "Private IP address of the edge/NAT VM"
  value       = module.edge.edge_private_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion (admin)"
  value       = "ssh ${var.jump_user}@${module.edge.edge_public_ip}"
}

# =============================================================================
# Team VM Outputs
# =============================================================================

output "team_vms" {
  description = "Map of team VM names to their private IPs"
  value       = { for team_id, team_vm in module.team_vm : team_id => team_vm.private_ip }
}

output "team_ssh_commands" {
  description = "SSH commands to connect to team VMs (using generated keys)"
  value = {
    for team_id, team_config in var.teams :
    team_id => "ssh -F ~/.ssh/ai-camp/ssh-config ${team_config.user}"
  }
}

# =============================================================================
# DNS Configuration
# =============================================================================

output "dns_records" {
  description = "DNS records to configure"
  value = {
    wildcard = "*.${var.domain} -> ${module.edge.edge_public_ip}"
    bastion  = "bastion.${var.domain} -> ${module.edge.edge_public_ip}"
  }
}

# =============================================================================
# Team Credentials Location
# =============================================================================

output "team_credentials_folders" {
  description = "Location of generated credentials for each team"
  value = {
    for team_id, team_config in var.teams :
    team_id => "secrets/team-${team_id}/"
  }
}

output "credentials_summary" {
  description = "Path to JSON file with all team credentials"
  value       = length(var.teams) > 0 ? "secrets/teams-credentials.json" : null
}
