variable "name" {
  description = "Base name for edge resources"
  type        = string
}

variable "zone" {
  description = "Yandex Cloud availability zone"
  type        = string
}

variable "platform" {
  description = "Platform ID for the VM"
  type        = string
  default     = "standard-v3"
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory in GB"
  type        = number
  default     = 4
}

variable "disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 30
}

variable "preemptible" {
  description = "Whether the VM is preemptible"
  type        = bool
  default     = false
}

variable "public_subnet_id" {
  description = "ID of the public subnet"
  type        = string
}

variable "edge_sg_id" {
  description = "ID of the edge security group"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR of the private subnet (for NAT rules)"
  type        = string
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

variable "traefik_config" {
  description = "Traefik configuration content"
  type        = string
}

variable "xray_config" {
  description = "Xray configuration content"
  type        = string
}
