# =============================================================================
# Ubuntu Image Data Source
# =============================================================================

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

# =============================================================================
# Edge/NAT VM Instance
# =============================================================================

resource "yandex_compute_instance" "edge" {
  name        = "${var.name}-edge"
  hostname    = "edge"
  platform_id = var.platform
  zone        = var.zone

  resources {
    cores         = var.cores
    memory        = var.memory
    core_fraction = var.core_fraction
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = var.disk_size
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id          = var.public_subnet_id
    nat                = true
    security_group_ids = [var.edge_sg_id]
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init.tpl", {
      jump_user           = var.jump_user
      jump_public_key     = var.jump_public_key
      traefik_config      = var.traefik_config
      xray_config         = var.xray_config
      private_subnet_cidr = var.private_subnet_cidr
      vless_server_ip     = var.vless_server_ip
    })
  }

  scheduling_policy {
    preemptible = var.preemptible
  }

  allow_stopping_for_update = true

  lifecycle {
    ignore_changes = [
      boot_disk[0].initialize_params[0].image_id
    ]
  }
}
