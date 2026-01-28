output "edge_sg_id" {
  description = "ID of the edge security group"
  value       = yandex_vpc_security_group.edge.id
}

output "team_sg_id" {
  description = "ID of the team security group"
  value       = yandex_vpc_security_group.team.id
}
