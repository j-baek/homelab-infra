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

### Overlay disk for k3s VM
# The actual disk the VM will use.
# It only stores what changes, and the base (ubuntu) stays untouched.
resource "libvirt_volume" "k3s_disk" {
  name     = "k3s.qcow2"
  pool     = "default"
  capacity = 107374182400 # 100 GB storage for VM

  backing_store = {
    path = libvirt_volume.ubuntu_base.path
    format = {
      type = "qcow2"
    }
  }
}
