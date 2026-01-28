variable "name" {
  description = "Base name for routing resources"
  type        = string
}

variable "network_id" {
  description = "ID of the VPC network"
  type        = string
}

variable "nat_gateway_ip" {
  description = "Private IP address of the NAT gateway (edge VM)"
  type        = string
}
