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
  description = "SSH command to connect to bastion"
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
  description = "SSH commands to connect to team VMs via jump host"
  value = {
    for team_id, team_config in var.teams :
    team_id => "ssh -J ${var.jump_user}@${module.edge.edge_public_ip} ${team_config.user}@${module.team_vm[team_id].private_ip}"
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
# Generated SSH Keys (if enabled)
# =============================================================================

output "generated_public_keys" {
  description = "Generated public keys for teams (if generate_ssh_keys is enabled)"
  value       = var.generate_ssh_keys ? { for team_id, key in tls_private_key.team_keys : team_id => key.public_key_openssh } : {}
  sensitive   = false
}
