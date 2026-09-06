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
  firewall_ids = [hcloud_firewall.zero_trust.id]

    labels = {
        project = "secure-vps"
        managed_by = "terraform"
    }
} 
