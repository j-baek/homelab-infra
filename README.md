# homelab

A personal home lab that turns an unused laptop into a virtualization host running k3s (lightweight Kubernetes) via the **KVM/QEMU/Libvirt** stack, managed as Infrastructure-as-Code with **Terraform**.

---

## What is the KVM/QEMU/Libvirt stack?

| Layer | Role |
|---|---|
| **KVM** (Kernel-based Virtual Machine) | Linux kernel module that exposes hardware virtualization extensions (AMD-V / Intel VT-x). It turns the Linux kernel itself into a type-1 (bare-metal) hypervisor. |
| **QEMU** | User-space machine emulator. It creates and drives virtual CPUs, memory, disk, and network devices. When paired with KVM, QEMU hands hot paths to the kernel instead of emulating them in software, so VMs run near-native speed. |
| **Libvirt** | Management daemon (`libvirtd`) + API that sits above QEMU/KVM. It provides a stable, hypervisor-agnostic interface for creating, starting, stopping, and introspecting VMs. Tools like `virsh`, `virt-manager`, and the Terraform `libvirt` provider all talk to libvirt. |

In short: **KVM** makes virtualization fast, **QEMU** implements the virtual hardware, and **Libvirt** makes both manageable.

---

## Goal

Convert unsued laptop into a single-node virtualization host and provision one or more VMs running **k3s** (a minimal, production-grade Kubernetes distribution). Terraform drives the full lifecycle — from creating disk images and cloud-init configs to defining the VM domain in libvirt.

---

## Current Host hardware

| Resource | Spec |
|---|---|
| **CPU** | AMD Ryzen 5 PRO 3500U (4 cores / 8 threads) |
| **RAM** | 13 GB total — ~10 GB available for VMs |
| **Storage** | 238.5 GB NVMe SSD — ~178 GB free on `/` |
| **Swap** | 4 GB |

### Suggested VM allocation (single-node k3s)

| Resource | Host reserve | VM budget |
|---|---|---|
| vCPUs | 2 | 6 |
| RAM | 2 GB | 8 GB |
| Disk | — | up to 150 GB |

---

## Stack

- **Hypervisor**: KVM + QEMU
- **VM management**: Libvirt (`qemu:///system`)
- **IaC**: Terraform (`dmacvicar/libvirt` provider v0.9.2)
- **Kubernetes**: k3s

---

## Repository layout

```
terraform/
  provider.tf   # libvirt provider wired to qemu:///system
  versions.tf   # Terraform ≥1.15, libvirt provider 0.9.2
  main.tf       # VM definitions (WIP)
```
