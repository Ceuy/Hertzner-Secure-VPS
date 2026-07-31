variable "hcloud_token" {
  description = "The API token for Hetzner Cloud"
  type = string
  sensitive = true
  }

variable "hcloud_server_name" {
  description = "The name of the VPS to create"
  type        = string
  default     = "secure-vps"
}

variable "server_type" {
  description = "Hetzner server type"
  type        = string
  default     = "cx23"
}

variable "location" {
  description = "Hetzner server location"
  type        = string
  default     = "hel1"
}

variable "image" {
  description = "Hetzner server image"
  type        = string
  default     = "ubuntu-26.04"
}

variable "ssh_public_key" {
  description = "The public SSH key to use for the server"
  type        = string
  default     = "~/.ssh/id_ed25519_vps.pub"
}

variable "bootstrap_ssh_cidr" {
  description = "Temporary CIDR for SSH before Tailscale is setup"
  type        = string
}