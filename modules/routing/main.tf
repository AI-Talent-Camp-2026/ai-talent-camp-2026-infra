# =============================================================================
# Route Table for NAT through Edge VM
# =============================================================================

resource "yandex_vpc_route_table" "nat" {
  name        = "${var.name}-nat-route"
  description = "Route table for NAT through edge VM"
  network_id  = var.network_id

  static_route {
    destination_prefix = "0.0.0.0/0"
    next_hop_address   = var.nat_gateway_ip
  }
}

# =============================================================================
# Attach Route Table to Private Subnet
# =============================================================================

# Note: In Yandex Cloud, route_table_id is set on the subnet resource.
# We need to update the private subnet to use this route table.
# This is done by creating a new subnet with the route table attached,
# or by using a separate resource to manage the binding.

# Since we cannot modify the subnet created in the network module directly,
# we output the route table ID and the private subnet should be recreated
# with the route table attached in the environment configuration.

# Alternative: Use yandex_vpc_subnet data source and recreate with route table
# For now, we just create the route table and output its ID.
# The binding will be handled in the environment main.tf
