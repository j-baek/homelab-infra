### Base volume ### 
# Download Ubuntu 24.04 cloud image and store it as a base volume.
resource "libvirt_volume" "ubuntu_base" {
  name = "ubuntu-24.04-base.qcow2"
  pool = "default"
  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
    }
  }
}

### k3s cluster nodes
# 1 server (control plane) + 2 agents (workers)
locals {
  k3s_nodes = toset(["server", "agent-1", "agent-2"])
}

### Overlay disk per node
# Each node gets its own disk. It only stores what changes,
# and the base (ubuntu) image stays untouched.
resource "libvirt_volume" "k3s_disk" {
  for_each = local.k3s_nodes

  name     = "${each.key}.qcow2"
  pool     = "default"
  capacity = 32212254720 # 30 GB storage per VM

  backing_store = {
    path = libvirt_volume.ubuntu_base.path
    format = {
      type = "qcow2"
    }
  }
}
