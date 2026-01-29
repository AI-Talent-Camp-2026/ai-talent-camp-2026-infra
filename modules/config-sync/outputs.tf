# =============================================================================
# Config Sync Module - Outputs
# =============================================================================

output "traefik_auto_config_path" {
  description = "Path to auto-generated Traefik config"
  value       = length(var.teams) > 0 ? local_file.traefik_dynamic_auto[0].filename : null
}

output "traefik_custom_config_path" {
  description = "Path to custom Traefik config"
  value       = length(var.teams) > 0 ? local_file.traefik_dynamic_custom[0].filename : null
}
