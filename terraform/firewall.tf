resource "hcloud_firewall" "zero_trust" {
  name = "${var.hcloud_server_name}-fw"

#temp bootstrap SSH - remove when Tailscale is setup
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      var.bootstrap_ssh_cidr
    ]
  }
#tailscale mesh (UDP)
  rule {
    direction = "in"
    protocol  = "udp"
    port      = "41641"
    source_ips = [
      "0.0.0.0/0"
    ]
  }

#allow all outbound traffic
  rule {
    direction = "out"
    protocol  = "tcp"
    port      = "1-65535"
    destination_ips = [
      "0.0.0.0/0","::/0"
]
}
rule {
    direction = "out"
    protocol  = "udp"
    port      = "1-65535"
    destination_ips = [
      "0.0.0.0/0","::/0"]
}

}