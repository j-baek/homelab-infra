locals {
  # Encode data as YAML: never interpolate the token into shell commands.
  cloud_config = { for name, node in var.nodes : name => {
    hostname         = "${var.cluster_name}-${name}"
    manage_etc_hosts = true
    ssh_pwauth       = false
    disable_root     = true
    users = [{
      name                = var.ssh_user
      groups              = ["sudo"]
      shell               = "/bin/bash"
      lock_passwd         = true
      sudo                = "ALL=(ALL) NOPASSWD:ALL"
      ssh_authorized_keys = [local.ssh_public_key]
    }]
    write_files = [
      {
        path        = "/etc/rancher/k3s/config.yaml"
        owner       = "root:root"
        permissions = "0600"
        content = yamlencode(merge({
          token         = var.k3s_token
          node-name     = "${var.cluster_name}-${name}"
          node-ip       = local.node_ips[name]
          flannel-iface = "eth0"
          }, jsondecode(node.role == "server" ? jsonencode({
            write-kubeconfig-mode = "0600"
            tls-san               = [local.server_ip]
        }) : jsonencode({ server = "https://${local.server_ip}:6443" }))))
      },
      {
        path        = "/usr/local/sbin/homelab-bootstrap"
        owner       = "root:root"
        permissions = "0750"
        content = templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
          version = var.k3s_version
          role    = node.role
        })
      },
      {
        path        = "/etc/systemd/system/homelab-bootstrap.service"
        owner       = "root:root"
        permissions = "0644"
        content     = file("${path.module}/templates/homelab-bootstrap.service")
      }
    ]
    runcmd = [
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "--now", "--no-block", "homelab-bootstrap.service"]
    ]
  } }
}

resource "libvirt_cloudinit_disk" "node" {
  for_each = var.nodes
  name     = "${var.cluster_name}-${each.key}-seed"
  meta_data = yamlencode({
    instance-id    = "${var.cluster_name}-${each.key}"
    local-hostname = "${var.cluster_name}-${each.key}"
  })
  user_data = "#cloud-config\n${yamlencode(local.cloud_config[each.key])}"
  network_config = yamlencode({
    version = 2
    ethernets = { eth0 = {
      match    = { macaddress = each.value.mac }
      set-name = "eth0"
      dhcp4    = true
      dhcp6    = false
    } }
  })
}

# Upload generated seed media into the pool; QEMU need not traverse the user's
# home directory. Seed media contains credentials, so keep host access restricted.
resource "libvirt_volume" "seed" {
  for_each = var.nodes
  name     = "${var.cluster_name}-${each.key}-seed.iso"
  pool     = libvirt_pool.default.name
  target = {
    format      = { type = "iso" }
    permissions = { mode = "0600" }
  }
  create = { content = { url = libvirt_cloudinit_disk.node[each.key].path } }
  lifecycle {
    replace_triggered_by = [libvirt_cloudinit_disk.node[each.key]]
  }
}
