output "nodes" {
  description = "Expected node addresses; scripts/lab.py check verifies live readiness."
  value = { for name, node in var.nodes : name => {
    name = libvirt_domain.node[name].name
    ip   = local.node_ips[name]
    role = node.role
    user = var.ssh_user
  } }
}

output "server_ip" {
  description = "Private Kubernetes API address, reachable from the libvirt host."
  value       = local.server_ip
}
