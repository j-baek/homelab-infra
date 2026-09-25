locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
  server_name    = one([for name, node in var.nodes : name if node.role == "server"])
  node_ips       = { for name, node in var.nodes : name => cidrhost(var.network_cidr, node.host_number) }
  server_ip      = local.node_ips[local.server_name]
}

# This shared pool predates the lab and contains unrelated images. Keep its
# existing Terraform address; reject deletion/replacement while it is declared.
resource "libvirt_pool" "default" {
  name   = var.storage_pool_name
  type   = "dir"
  target = { path = var.storage_pool_path }
  lifecycle {
    prevent_destroy = true
  }
}

# Overlays depend on this image for unchanged blocks. Do not overwrite or delete
# the base while dependent disks exist. Downloading happens during creation only.
resource "libvirt_volume" "ubuntu_base" {
  name   = var.ubuntu_base_name
  pool   = libvirt_pool.default.name
  target = { format = { type = "qcow2" } }
  create = { content = { url = var.ubuntu_base_url } }
}

resource "libvirt_volume" "k3s_disk" {
  for_each = var.nodes
  name     = "${var.cluster_name}-${each.key}.qcow2"
  pool     = libvirt_pool.default.name
  capacity = each.value.disk_gib * 1024 * 1024 * 1024
  target   = { format = { type = "qcow2" } }
  backing_store = {
    path   = libvirt_volume.ubuntu_base.path
    format = { type = "qcow2" }
  }
}

# Guests use DHCP; matching MAC reservations make their addresses predictable.
# Only declared nodes need addresses, so there is no unreserved DHCP range.
resource "libvirt_network" "k3s_net" {
  name      = var.network_name
  autostart = true
  forward   = { mode = "nat" }
  bridge    = { name = var.bridge_name }
  ips = [{
    family  = "ipv4"
    address = cidrhost(var.network_cidr, 1)
    netmask = cidrnetmask(var.network_cidr)
    dhcp = { hosts = [for name, node in var.nodes : {
      name = "${var.cluster_name}-${name}"
      mac  = node.mac
      ip   = local.node_ips[name]
    }] }
  }]
}
