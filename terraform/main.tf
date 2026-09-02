### Base volume ### 
# Download Ubuntu 24.04 cloud image and store it as a base volume.
resource "libvirt_volume" "ubuntu_base" {
  name = var.ubuntu_base_name
  pool = "default"
  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = var.ubuntu_base_url
    }
  }
}

### k3s cluster nodes
# 1 server (control plane) + 2 agents (workers)
# Each node gets a fixed MAC + IP so the network's DHCP always hands out
# the same address, and agents can reliably find the server.
locals {
  k3s_nodes = {
    server  = { mac = "52:54:00:12:34:10", ip = "192.168.100.10" }
    agent-1 = { mac = "52:54:00:12:34:11", ip = "192.168.100.11" }
    agent-2 = { mac = "52:54:00:12:34:12", ip = "192.168.100.12" }
  }

  ssh_public_key = trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))
}

### Overlay disk per node
# Each node gets its own disk. It only stores what changes,
# and the base (ubuntu) image stays untouched.
resource "libvirt_volume" "k3s_disk" {
  for_each = local.k3s_nodes

  name     = "${each.key}-qcow2"
  pool     = "default"
  capacity = var.per_vm_storage

  backing_store = {
    path = libvirt_volume.ubuntu_base.path
    format = {
      type = "qcow2"
    }
  }
}

### Dedicated virtual network for the k3s cluster
# Separate from libvirt's "default" network (192.168.122.0/24) so we can
# control the DHCP range and reserve fixed IPs without any collision risk.
resource "libvirt_network" "k3s_net" {
  name      = "k3s-net"
  autostart = true

  forward = {
    mode = "nat"
  }

  bridge = {
    name = "virbr-k3s"
  }

  ips = [
    {
      family  = "ipv4"
      address = "192.168.100.1"
      netmask = "255.255.255.0"

      dhcp = {
        ## Optional: define a range of IPs to hand out via DHCP, which won't get static IP,
        ## used for test/temporary nodes that don't require a fixed IP.
        #ranges = [
        #{
        #start = "192.168.100.100"
        #end   = "192.168.100.200"
        #}
        #]

        # Static reservations: each node's MAC always gets the same IP.
        hosts = [
          for name, node in local.k3s_nodes : {
            name = name
            mac  = node.mac
            ip   = node.ip
          }
        ]
      }
    }
  ]
}
