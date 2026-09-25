resource "libvirt_domain" "node" {
  for_each    = var.nodes
  name        = "${var.cluster_name}-${each.key}"
  type        = "kvm"
  memory      = each.value.memory_mib
  memory_unit = "MiB"
  vcpu        = each.value.vcpu
  running     = true
  autostart   = true
  cpu         = { mode = "host-passthrough" }
  features    = { acpi = true }
  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [{ dev = "hd" }]
  }
  devices = {
    disks = [
      {
        device = "disk"
        driver = { name = "qemu", type = "qcow2" }
        source = { file = { file = libvirt_volume.k3s_disk[each.key].path } }
        target = { dev = "vda", bus = "virtio" }
      },
      {
        device    = "cdrom"
        driver    = { name = "qemu", type = "raw" }
        source    = { file = { file = libvirt_volume.seed[each.key].path } }
        target    = { dev = "sda", bus = "sata" }
        read_only = true
      }
    ]
    interfaces = [{
      source      = { network = { network = libvirt_network.k3s_net.name } }
      model       = { type = "virtio" }
      mac         = { address = each.value.mac }
      wait_for_ip = { source = "lease", timeout = 300 }
    }]
    # Serial access remains available when guest networking or SSH fails.
    consoles = [{ target = { type = "serial", port = 0 } }]
  }
}
