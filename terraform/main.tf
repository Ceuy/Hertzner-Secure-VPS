resource "hcloud_ssh_key" "default" {
  name       = "${var.hcloud_server_name}-key"
  public_key = file(var.ssh_public_key)
}

resource "hcloud_server" "vps" {
  name        = var.hcloud_server_name
  server_type = var.server_type
  location    = var.location
  image       = var.image

  ssh_keys = [hcloud_ssh_key.default.id]

    labels = {
        project = "secure-vps"
        managed_by = "terraform"
    }
/*
  # Temporary firewall rule to allow SSH from a specific CIDR before Tailscale is set up
  user_data = <<-EOF
              #cloud-config
              runcmd:
                - ufw allow from ${var.bootstrap_ssh_cidr} to any port 22 proto tcp
                - ufw enable
              EOF
              */
} 