# =============================================================================
# Config Sync Module - Variables
# =============================================================================

variable "edge_public_ip" {
  description = "Public IP address of edge/bastion server"
  type        = string
}

variable "jump_user" {
  description = "Username for jump host access"
  type        = string
}

variable "jump_private_key_path" {
  description = "Path to admin's private SSH key for bastion access"
  type        = string
}

variable "teams" {
  description = "Map of teams with their configuration"
  type = map(object({
    user       = string
    private_ip = string
  }))
}

variable "team_jump_keys" {
  description = "Map of team jump keys with their VM IPs for restricted access"
  type = map(object({
    public_key = string
    vm_ip      = string
  }))
}

variable "domain" {
  description = "Base domain for the infrastructure"
  type        = string
}

variable "xray_config" {
  description = "Xray configuration content"
  type        = string
  sensitive   = true
}

variable "secrets_path" {
  description = "Path to secrets directory"
  type        = string
  default     = "../../secrets"
}

variable "enable_traefik_sync" {
  description = "Enable Traefik configuration sync"
  type        = bool
  default     = true
}
