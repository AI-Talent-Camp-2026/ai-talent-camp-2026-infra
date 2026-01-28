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
  default     = 30
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
  default     = 2
}

variable "team_memory" {
  description = "Memory in GB for team VMs"
  type        = number
  default     = 4
}

variable "team_disk_size" {
  description = "Boot disk size in GB for team VMs"
  type        = number
  default     = 30
}

variable "teams" {
  description = "Map of teams with their configuration"
  type = map(object({
    user        = string
    public_keys = list(string)
  }))
  default = {}
}

# =============================================================================
# Xray/VLESS Configuration
# =============================================================================

variable "vless_server" {
  description = "VLESS proxy server address"
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

variable "proxy_domains" {
  description = "List of domains to route through VLESS proxy"
  type        = list(string)
  default = [
    "api.openai.com",
    "api.anthropic.com",
    "generativelanguage.googleapis.com",
    "api.groq.com"
  ]
}
