output "edge_public_ip" {
  description = "Public IP address of the edge VM"
  value       = yandex_compute_instance.edge.network_interface[0].nat_ip_address
}

output "edge_private_ip" {
  description = "Private IP address of the edge VM"
  value       = yandex_compute_instance.edge.network_interface[0].ip_address
}

output "edge_instance_id" {
  description = "Instance ID of the edge VM"
  value       = yandex_compute_instance.edge.id
}

output "edge_fqdn" {
  description = "FQDN of the edge VM"
  value       = yandex_compute_instance.edge.fqdn
}
