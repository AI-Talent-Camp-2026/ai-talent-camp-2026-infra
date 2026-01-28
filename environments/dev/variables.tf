# =============================================================================
# Yandex Cloud Configuration
# =============================================================================

variable "folder_id" {
  description = "Yandex Cloud folder ID"
  type        = string
}

variable "zone" {
  description = "Yandex Cloud availability zone"
  type        = string
  default     = "ru-central1-a"
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "ai-camp-network"
}

variable "public_cidr" {
  description = "CIDR block for public subnet (edge/NAT)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_cidr" {
  description = "CIDR block for private subnet (team VMs)"
  type        = string
  default     = "10.0.2.0/24"
}

# =============================================================================
# Project Configuration
# =============================================================================

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "ai-camp"
}

variable "domain" {
  description = "Base domain for the camp"
  type        = string
  default     = "camp.aitalenthub.ru"
}

# =============================================================================
# Edge VM Configuration
# =============================================================================

variable "edge_platform" {
  description = "Platform ID for edge VM"
  type        = string
  default     = "standard-v3"
}

variable "edge_cores" {
  description = "Number of CPU cores for edge VM"
  type        = number
  default     = 2
}

variable "edge_memory" {
  description = "Memory in GB for edge VM"
  type        = number
  default     = 4
}

variable "edge_disk_size" {
  description = "Boot disk size in GB for edge VM"
  type        = number
  default     = 20
}

variable "edge_core_fraction" {
  description = "Guaranteed vCPU share for edge VM (50, 100)"
  type        = number
  default     = 100
}

variable "edge_preemptible" {
  description = "Whether edge VM is preemptible (cheaper but can be stopped)"
  type        = bool
  default     = false
}

variable "jump_user" {
  description = "Username for jump host access"
  type        = string
  default     = "jump"
}

variable "jump_public_key" {
  description = "SSH public key for jump host user"
  type        = string
}

# =============================================================================
# Team VM Configuration
# =============================================================================

variable "team_platform" {
  description = "Platform ID for team VMs"
  type        = string
  default     = "standard-v3"
}

variable "team_cores" {
  description = "Number of CPU cores for team VMs"
  type        = number
  default     = 4
}

variable "team_memory" {
  description = "Memory in GB for team VMs"
  type        = number
  default     = 8
}

variable "team_disk_size" {
  description = "Boot disk size in GB for team VMs"
  type        = number
  default     = 65
}

variable "team_core_fraction" {
  description = "Guaranteed vCPU share for team VMs (50, 100)"
  type        = number
  default     = 100
}

variable "team_preemptible" {
  description = "Whether team VMs are preemptible"
  type        = bool
  default     = false
}

variable "teams" {
  description = "Map of teams with their configuration. SSH keys are auto-generated for each team."
  type = map(object({
    user        = string
    public_keys = list(string)  # Additional keys (optional)
  }))
  default = {}
}

# =============================================================================
# Xray/VLESS Configuration
# =============================================================================

variable "vless_server" {
  description = "VLESS proxy server address (hostname)"
  type        = string
  default     = ""
}

variable "vless_server_ip" {
  description = "VLESS server IP address (excluded from TPROXY to avoid loop)"
  type        = string
  default     = ""
}

variable "vless_port" {
  description = "VLESS proxy server port"
  type        = number
  default     = 443
}

variable "vless_uuid" {
  description = "VLESS UUID for authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vless_sni" {
  description = "VLESS Reality SNI (serverName)"
  type        = string
  default     = ""
}

variable "vless_fingerprint" {
  description = "VLESS Reality browser fingerprint"
  type        = string
  default     = "chrome"
}

variable "vless_public_key" {
  description = "VLESS Reality public key"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vless_short_id" {
  description = "VLESS Reality short ID"
  type        = string
  default     = ""
  sensitive   = true
}
