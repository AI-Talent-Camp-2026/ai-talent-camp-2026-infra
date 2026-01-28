output "private_ip" {
  description = "Private IP address of the team VM"
  value       = yandex_compute_instance.team.network_interface[0].ip_address
}

output "instance_id" {
  description = "Instance ID of the team VM"
  value       = yandex_compute_instance.team.id
}

output "fqdn" {
  description = "FQDN of the team VM"
  value       = yandex_compute_instance.team.fqdn
}

output "hostname" {
  description = "Hostname of the team VM"
  value       = yandex_compute_instance.team.hostname
}
