# Design and operations notes

This file explains the implementation and its limits. `README.md` is the operating
guide; Terraform source is the configuration. A written configuration or saved
state is not proof that resources are currently healthy.

## How the pieces fit

```text
Terraform -> libvirt -> QEMU using KVM -> Ubuntu guests
                                |
                       cloud-init first boot
                                |
                  retryable bootstrap systemd unit
                                |
                  k3s server + two k3s agents
```

KVM provides hardware acceleration. QEMU supplies each guest's virtual hardware.
Libvirt exposes a management API, and Terraform records the resources it manages
in state. k3s runs Kubernetes inside the guests; Terraform does not manage deployed
Kubernetes applications in this repository.

The single server also runs worker components. The two agents add learning and
workload capacity, but no control-plane redundancy. All three share one physical
failure domain: the laptop.

## libvirt pools and volumes

Related code: `terraform/main.tf`. Defaults: `terraform/variables.tf`.

### Pool: a place to store disk files

`libvirt_pool.default` registers and manages a host directory as libvirt storage.
This project uses `type = "dir"`, which means a directory storage pool.

- `name`: the pool name used by libvirt. The default is `default`.
- `target.path`: the host directory containing the files. The default is
  `/var/lib/libvirt/images`.
- `prevent_destroy = true`: blocks Terraform from deleting or replacing the pool
  while this setting is declared. It does not prevent someone from deleting files
  manually.

The `default` in `resource "libvirt_pool" "default"` is Terraform's local resource
name. `name = var.storage_pool_name` sets the actual pool name in libvirt.

### Volume: an individual storage item inside a pool

`libvirt_volume` manages one storage item in a pool. In this project's directory
pool, think of it as a virtual disk file. A VM uses its attached virtual disk as
its own hard drive.

| Resource | Role |
|---|---|
| `libvirt_pool.default` | The place where disk files are stored |
| `libvirt_volume.ubuntu_base` | The Ubuntu base image shared by all three VMs |
| `libvirt_volume.k3s_disk` | A separate disk storing each VM's changes |

### ubuntu_base: a shared starting point with Ubuntu already installed

`create.content.url = var.ubuntu_base_url` downloads an Ubuntu cloud image into
the pool. This is a bootable disk image containing Ubuntu, rather than an installer
ISO that opens an installation wizard. `target.format.type = "qcow2"` specifies
the disk file format.

Each VM disk references this one base image, avoiding a separate full copy of
Ubuntu for every VM.

### k3s_disk: a separate disk for each VM

`for_each = var.nodes` creates one volume per node. With the default configuration,
the three VM disks share one base image:

```text
/var/lib/libvirt/images/          <- default pool directory
├── ubuntu-24.04-base.qcow2       <- shared base image
├── k3s-server.qcow2              <- server's changes
├── k3s-agent-1.qcow2             <- agent-1's changes
└── k3s-agent-2.qcow2             <- agent-2's changes
```

This diagram shows only the disks discussed here.

```hcl
backing_store = {
  path   = libvirt_volume.ubuntu_base.path
  format = { type = "qcow2" }
}
```

`backing_store` specifies the base image for a VM disk. A disk that stores changes
on top of a base image is called an **overlay**.

### Copy-on-write: share reads and keep changes separate

1. If the requested data is already stored in the VM's overlay, read it there.
2. Otherwise, read the data from `ubuntu_base`.
3. Write new or modified data to that VM's overlay.

For example, installing k3s or editing an Ubuntu configuration file on the server
writes changes to `k3s-server.qcow2`. The other VM disks and the shared base image
remain unchanged. This applies to all disk writes, including Ubuntu updates and
user files. The mechanism operates on disk data blocks, rather than whole files.

The overlays still depend on data in the base image. Do not delete or overwrite
`ubuntu_base` while the overlays depend on it. Copying an overlay alone does not
produce a complete, independent disk.
