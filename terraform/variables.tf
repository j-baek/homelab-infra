variable "libvirt_uri" {
  description = "Local system libvirt connection; helper scripts run on this host."
  type        = string
  default     = "qemu:///system"
  validation {
    condition     = var.libvirt_uri == "qemu:///system"
    error_message = "This lab supports the local qemu:///system connection only."
  }
}

variable "cluster_name" {
  description = "Prefix for VM, disk, and guest names. Review replacements when changing it."
  type        = string
  default     = "k3s"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,19}$", var.cluster_name))
    error_message = "Use a lowercase hostname prefix of 1-20 characters."
  }
}

variable "storage_pool_name" {
  description = "Shared directory pool; import it at libvirt_pool.default if it already exists."
  type        = string
  default     = "default"
}

variable "storage_pool_path" {
  description = "Existing pool directory. Changing a populated pool requires a planned migration."
  type        = string
  default     = "/var/lib/libvirt/images"
}

variable "ubuntu_base_name" {
  description = "Base-image volume name; overlays depend on this image throughout their lifetime."
  type        = string
  default     = "ubuntu-24.04-base.qcow2"
}

variable "ubuntu_base_url" {
  description = "Ubuntu amd64 image URL; a dated release URL makes fresh rebuilds more reproducible."
  type        = string
  default     = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
}

variable "ssh_public_key_path" {
  description = "Public key installed for the guest administrator; private keys stay on the host."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_user" {
  description = "Guest administrator with passwordless sudo and key-only SSH access."
  type        = string
  default     = "ubuntu"
  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,30}$", var.ssh_user)) && var.ssh_user != "root"
    error_message = "Use a valid non-root Linux username."
  }
}

variable "k3s_token" {
  description = "Join secret: stored in private tfvars, Terraform state, and seed media."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.k3s_token) >= 32 && trimspace(var.k3s_token) == var.k3s_token && !startswith(var.k3s_token, "REPLACE_")
    error_message = "Supply a join token of at least 32 characters without surrounding whitespace."
  }
}

variable "k3s_version" {
  description = "Exact release for new guests; changing cloud-init does not upgrade existing guests."
  type        = string
  default     = "v1.36.4+k3s1"
  validation {
    condition     = can(regex("^v[0-9]+[.][0-9]+[.][0-9]+[+]k3s[0-9]+$", var.k3s_version))
    error_message = "Use an exact release such as v1.36.4+k3s1."
  }
}

variable "network_name" {
  description = "Dedicated libvirt NAT network name."
  type        = string
  default     = "k3s-net"
}

variable "bridge_name" {
  description = "Host bridge interface name (Linux limit: 15 characters)."
  type        = string
  default     = "virbr-k3s"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]{0,14}$", var.bridge_name))
    error_message = "Use a valid interface name up to 15 characters."
  }
}

variable "network_cidr" {
  description = "IPv4 /24 for guests; .1 is the gateway. Check host and VPN overlap before applying."
  type        = string
  default     = "192.168.100.0/24"
  validation {
    condition     = can(cidrnetmask(var.network_cidr)) && can(regex("/24$", var.network_cidr))
    error_message = "Supply an IPv4 /24 network."
  }
}

# Keep node names lowercase; use unique host numbers (2-254) and unique lowercase
variable "nodes" {
  description = "One server plus agents. RAM is MiB, disk is GiB, host_number selects the subnet address."
  type = map(object({
    role        = string
    host_number = number
    mac         = string
    vcpu        = number
    memory_mib  = number
    disk_gib    = number
  }))
  default = {
    server  = { role = "server", host_number = 10, mac = "52:54:00:12:34:10", vcpu = 2, memory_mib = 4096, disk_gib = 30 }
    agent-1 = { role = "agent", host_number = 11, mac = "52:54:00:12:34:11", vcpu = 2, memory_mib = 2048, disk_gib = 30 }
    agent-2 = { role = "agent", host_number = 12, mac = "52:54:00:12:34:12", vcpu = 2, memory_mib = 2048, disk_gib = 30 }
  }
  validation {
    condition     = length([for n in var.nodes : n if n.role == "server"]) == 1 && alltrue([for n in var.nodes : contains(["server", "agent"], n.role)])
    error_message = "Declare exactly one server; other nodes must be agents."
  }
}
