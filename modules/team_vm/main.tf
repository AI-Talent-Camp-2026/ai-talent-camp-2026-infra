# =============================================================================
# Ubuntu Image Data Source
# =============================================================================

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

# =============================================================================
# Team VM Instance
# =============================================================================

resource "yandex_compute_instance" "team" {
  name        = "${var.name}-team-${var.team_id}"
  hostname    = "team-${var.team_id}"
  platform_id = var.platform
  zone        = var.zone

  resources {
    cores  = var.cores
    memory = var.memory
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = var.disk_size
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id          = var.private_subnet_id
    nat                = false # No public IP - traffic goes through NAT
    security_group_ids = [var.team_sg_id]
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init.tpl", {
      team_user   = var.team_user
      public_keys = var.public_keys
      domain      = var.domain
      team_id     = var.team_id
    })
  }

  scheduling_policy {
    preemptible = var.preemptible
  }

  allow_stopping_for_update = true
}
