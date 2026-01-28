output "route_table_id" {
  description = "ID of the NAT route table"
  value       = yandex_vpc_route_table.nat.id
}
