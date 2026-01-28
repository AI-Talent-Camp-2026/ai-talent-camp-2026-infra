output "network_id" {
  description = "ID of the created VPC network"
  value       = yandex_vpc_network.this.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = yandex_vpc_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet (null if not created)"
  value       = var.create_private_subnet ? yandex_vpc_subnet.private[0].id : null
}

output "public_subnet_cidr" {
  description = "CIDR block of the public subnet"
  value       = var.public_cidr
}

output "private_subnet_cidr" {
  description = "CIDR block of the private subnet"
  value       = var.private_cidr
}
