variable "name" {
  description = "Base name for security groups"
  type        = string
}

variable "network_id" {
  description = "ID of the VPC network"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR block of the private subnet (for NAT traffic rules)"
  type        = string
}
