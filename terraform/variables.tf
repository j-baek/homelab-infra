variable "k3s_token" {
  description = "Shared secret agents use to join the k3s server"
  type        = string
  sensitive   = true
}

variable "ubuntu_base_name" {
  description = "Name of the base Ubuntu image to use for the VMs"
  type        = string
  default     = "ubuntu-24.04-base.qcow2"
}

variable "ubuntu_base_url" {
  description = "URL to download the base Ubuntu image if it doesn't exist"
  type        = string
  default     = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
}

variable "per_vm_storage" {
  description = "Storage size in GB for each VM's overlay disk"
  type        = number
  default     = 32212254720 # 30 GB
}