locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
  server_name    = one([for name, node in var.nodes : name if node.role == "server"])
  node_ips       = { for name, node in var.nodes : name => cidrhost(var.network_cidr, node.host_number) }
  server_ip      = local.node_ips[local.server_name]
}

# Storage pool for managing storage volumes
resource "libvirt_pool" "default" {
  name   = var.storage_pool_name
  type   = "dir"
  target = { path = var.storage_pool_path }
  lifecycle {
    prevent_destroy = true
  }
}

# Download the Ubuntu cloud image into the storage pool as a shared base.
# Each VM disk below uses this volume as its qcow2 backing image.
resource "libvirt_volume" "ubuntu_base" {
  name   = var.ubuntu_base_name
  pool   = libvirt_pool.default.name
  target = { format = { type = "qcow2" } }
  create = { content = { url = var.ubuntu_base_url } }
}

# Create a disk for each node, using the shared base image as a backing store.
resource "libvirt_volume" "k3s_disk" {
  for_each      = var.nodes
  name          = "${var.cluster_name}-${each.key}.qcow2"
  pool          = libvirt_pool.default.name
  capacity      = each.value.disk_gib
  capacity_unit = "GiB"
  target        = { format = { type = "qcow2" } }
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
