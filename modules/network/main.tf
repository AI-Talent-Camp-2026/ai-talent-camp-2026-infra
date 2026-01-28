# =============================================================================
# VPC Network
# =============================================================================

resource "yandex_vpc_network" "this" {
  name        = var.network_name
  description = "VPC network for AI Camp infrastructure"
}

# =============================================================================
# Public Subnet (for Edge/NAT VM)
# =============================================================================

resource "yandex_vpc_subnet" "public" {
  name           = "${var.network_name}-public"
  description    = "Public subnet for edge/NAT server"
  zone           = var.zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [var.public_cidr]
}

# =============================================================================
# Private Subnet (for Team VMs)
# =============================================================================

resource "yandex_vpc_subnet" "private" {
  name           = "${var.network_name}-private"
  description    = "Private subnet for team VMs"
  zone           = var.zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [var.private_cidr]

  # Route table for NAT through edge VM
  route_table_id = var.route_table_id
}
