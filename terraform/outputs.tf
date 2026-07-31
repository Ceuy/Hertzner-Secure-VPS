output "server_ip" {
  value = hcloud_server.vps.ipv4_address
  description = "The public IP address of the VPS"
}

output "server_id" {
  value = hcloud_server.vps.id
  description = "The ID of the VPS"
}