# =============================================================================
# Edge Security Group
# =============================================================================

resource "yandex_vpc_security_group" "edge" {
  name        = "${var.name}-edge-sg"
  description = "Security group for edge/NAT server"
  network_id  = var.network_id

  # SSH access from anywhere
  ingress {
    protocol       = "TCP"
    description    = "SSH access"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }

  # HTTP access from anywhere
  ingress {
    protocol       = "TCP"
    description    = "HTTP access"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  # HTTPS access from anywhere
  ingress {
    protocol       = "TCP"
    description    = "HTTPS access"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  # Allow all traffic from private subnet (for NAT)
  ingress {
    protocol       = "ANY"
    description    = "All traffic from private subnet"
    v4_cidr_blocks = [var.private_subnet_cidr]
  }

  # ICMP for diagnostics
  ingress {
    protocol       = "ICMP"
    description    = "ICMP ping"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    protocol       = "ANY"
    description    = "Allow all outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# =============================================================================
# Team VM Security Group
# =============================================================================

resource "yandex_vpc_security_group" "team" {
  name        = "${var.name}-team-sg"
  description = "Security group for team VMs"
  network_id  = var.network_id

  # SSH access only from edge security group
  ingress {
    protocol          = "TCP"
    description       = "SSH from edge"
    security_group_id = yandex_vpc_security_group.edge.id
    port              = 22
  }

  # HTTP/HTTPS access only from edge security group (for Traefik proxy)
  ingress {
    protocol          = "TCP"
    description       = "HTTP from edge"
    security_group_id = yandex_vpc_security_group.edge.id
    port              = 80
  }

  ingress {
    protocol          = "TCP"
    description       = "HTTPS from edge"
    security_group_id = yandex_vpc_security_group.edge.id
    port              = 443
  }

  # Allow traffic between team VMs in the same security group
  ingress {
    protocol          = "ANY"
    description       = "Inter-team communication"
    predefined_target = "self_security_group"
  }

  # ICMP for diagnostics from edge
  ingress {
    protocol          = "ICMP"
    description       = "ICMP from edge"
    security_group_id = yandex_vpc_security_group.edge.id
  }

  # Allow all outbound traffic (through NAT)
  egress {
    protocol       = "ANY"
    description    = "Allow all outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
