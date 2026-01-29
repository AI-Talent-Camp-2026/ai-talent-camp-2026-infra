# =============================================================================
# Team Credentials Module - Variables
# =============================================================================

variable "teams" {
  description = "Map of teams with their configuration"
  type = map(object({
    user       = string
    private_ip = string
  }))
}

variable "domain" {
  description = "Base domain for the infrastructure"
  type        = string
}

variable "jump_user" {
  description = "Username for jump host access"
  type        = string
}

variable "bastion_ip" {
  description = "Public IP address of bastion host"
  type        = string
}

variable "secrets_path" {
  description = "Path to secrets directory"
  type        = string
  default     = "../../secrets"
}

# SSH Keys - passed from parent configuration
variable "team_jump_private_keys" {
  description = "Map of team jump private keys (OpenSSH format)"
  type        = map(string)
  sensitive   = true
}

variable "team_jump_public_keys" {
  description = "Map of team jump public keys (OpenSSH format)"
  type        = map(string)
}

variable "team_vm_private_keys" {
  description = "Map of team VM private keys (OpenSSH format)"
  type        = map(string)
  sensitive   = true
}

variable "team_vm_public_keys" {
  description = "Map of team VM public keys (OpenSSH format)"
  type        = map(string)
}

variable "team_github_private_keys" {
  description = "Map of team GitHub deploy private keys (OpenSSH format)"
  type        = map(string)
  sensitive   = true
}

variable "team_github_public_keys" {
  description = "Map of team GitHub deploy public keys (OpenSSH format)"
  type        = map(string)
}
