# =============================================================================
# Team Credentials Module - Outputs
# =============================================================================

output "credentials_files_created" {
  description = "Confirmation that credentials files were created"
  value       = length(var.teams) > 0 ? "Credentials created for ${length(var.teams)} team(s)" : "No teams configured"
}

output "credentials_summary_path" {
  description = "Path to the credentials summary JSON file"
  value       = local_file.teams_credentials_json.filename
}
