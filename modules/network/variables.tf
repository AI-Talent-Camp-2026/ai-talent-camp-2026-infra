variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "zone" {
  description = "Yandex Cloud availability zone"
  type        = string
}

variable "public_cidr" {
  description = "CIDR block for public subnet"
  type        = string
}

variable "private_cidr" {
  description = "CIDR block for private subnet"
  type        = string
}

variable "route_table_id" {
  description = "Route table ID to attach to private subnet (for NAT)"
  type        = string
  default     = null
}

variable "create_private_subnet" {
  description = "Whether to create private subnet (set to false if creating separately with route table)"
  type        = bool
  default     = true
}
