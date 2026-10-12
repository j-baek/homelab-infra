# Laptop k3s homelab

This repository builds three Ubuntu 24.04 virtual machines on a **local Linux
libvirt/KVM host**, then installs a pinned k3s Kubernetes release. Terraform owns
VMs, disks, a private network, and the existing directory storage pool. Cloud-init
sets up guest access and a retryable first-boot installer.

Think of Terraform as the building instructions, libvirt as the builder, the VMs
as separate computers inside your laptop, and k3s as their application coordinator.

| Guest | Role | Address | vCPUs | RAM | Disk capacity |
|---|---|---|---|---|---|
| k3s-server | Control plane and worker | 192.168.100.10 | 2 | 4 GiB | 30 GiB |
| k3s-agent-1 | Worker | 192.168.100.11 | 2 | 2 GiB | 30 GiB |
| k3s-agent-2 | Worker | 192.168.100.12 | 2 | 2 GiB | 30 GiB |

These are configurable defaults. All VMs share one physical host: this lab is
**not highly available**. A host failure stops the entire cluster. Disk capacities
are virtual maximums; copy-on-write allocation grows as guests write data.

## Requirements

- Linux x86-64 with hardware virtualization enabled, a usable `/dev/kvm`, and
  QEMU/libvirt installed and running.
- Access to `qemu:///system` through `virsh` as your normal user.
- Terraform satisfying `~> 1.15` (at least 1.15, below 2.0); tested CLI: 1.15.6.
  The committed lockfile selects `dmacvicar/libvirt` 0.9.9.
- Python 3, OpenSSH client, and `mkisofs`/`genisoimage` for cloud-init seed creation.
- An active directory pool, default `/var/lib/libvirt/images`, with sufficient
  free space. Budget for all three growing disks, the base image, and backups.
- At least 8 GiB available for the default guest allocations **plus host headroom**.
- Outbound HTTPS for Ubuntu images, package repositories, k3s, and container images.
- An SSH key pair. The public key defaults to `~/.ssh/id_ed25519.pub`.

Check the host before deploying:

```bash
virsh -c qemu:///system list --all
virsh -c qemu:///system pool-info default
virsh -c qemu:///system net-list --all
ls -l /dev/kvm
free -h
df -h /var/lib/libvirt/images
ip -4 route
```

The VM subnet must not overlap your LAN, Docker, or VPN networks. Also account for
k3s's default pod/service networks when connecting other networks later.

## Prepare a new Ubuntu 24.04 laptop

These host setup steps are for a fresh Ubuntu 24.04 x86-64 laptop. Other Linux
distributions need equivalent packages and libvirt configuration. Enable Intel
VT-x or AMD-V in firmware if necessary, then install the host tools:

```bash
sudo apt update
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients \
  genisoimage cpu-checker python3 openssh-client git openssl
sudo adduser "$USER" libvirt
```

Log out and back in so the new group membership takes effect. Install a Terraform
CLI version accepted by `terraform/versions.tf` (at least 1.15, below 2.0) using
the [official Terraform installation instructions](https://developer.hashicorp.com/terraform/install).
The provider is downloaded by `terraform -chdir=terraform init -lockfile=readonly` later;
do not install a different libvirt provider by hand.

Verify hardware acceleration and access to the **system** libvirt connection as
your normal user:

```bash
kvm-ok
ls -l /dev/kvm
virsh -c qemu:///system list --all
terraform version
```

The `default` libvirt storage pool is a name for a host directory, normally
`/var/lib/libvirt/images`. It may already exist after installing libvirt. Check
before creating anything:

```bash
virsh -c qemu:///system pool-list --all
virsh -c qemu:///system pool-dumpxml default
```

If `default` is **absent**, define and start a directory pool at the path used by
this repository. `pool-build` creates the directory if needed. Run these commands
only when the pool is absent:

```bash
virsh -c qemu:///system pool-define-as default dir --target /var/lib/libvirt/images
virsh -c qemu:///system pool-build default
virsh -c qemu:///system pool-start default
virsh -c qemu:///system pool-autostart default
```

If it is already defined but inactive, start it instead of defining it again:
`virsh -c qemu:///system pool-start default`. If autostart is disabled, enable it
with `virsh -c qemu:///system pool-autostart default`. Confirm that the pool XML
shows the intended path and `pool-info default` says it is running. Do not
replace or delete an existing pool to make its settings match; inspect its
contents and choose matching values for `storage_pool_name` and
`storage_pool_path` in your private tfvars file.

Create an SSH key if you do not already have one, and keep the private key on the
host. The default public-key path is `~/.ssh/id_ed25519.pub`:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
test -s ~/.ssh/id_ed25519.pub
```

Clone this repository onto the laptop. Before provisioning, run the host checks
in the Requirements section, confirm enough free RAM and disk space, and check that
`192.168.100.0/24` does not overlap any host, LAN, Docker, or VPN route. Then
continue with **Configure and deploy**. If you are moving an existing cluster
rather than building a fresh one, read the backup and recovery section in
`NOTES.md` first; a fresh apply does not restore its data or identity.

## Configure and deploy

Run commands from the repository root. `terraform -chdir=terraform` runs Terraform
using the configuration in the `terraform/` directory. Existing operators should
preserve their current `terraform.tfvars` and state; do not overwrite them with
example files.

For a new checkout:

```bash
cp -n terraform/terraform.tfvars.example terraform/terraform.tfvars
chmod 600 terraform/terraform.tfvars
openssl rand -hex 32
```

Put that newly generated secret in `k3s_token` in your private tfvars file. Do not
use the example placeholder. Set optional overrides in the same file; all inputs
and validation rules are in `terraform/variables.tf`.

The local tfvars file is the current approach. Moving `k3s_token` to HashiCorp
Vault or another secrets manager is planned; that integration is not implemented
yet.

```bash
terraform -chdir=terraform init -lockfile=readonly
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
```

**Existing shared storage pool:** this repository retains the address
`libvirt_pool.default` and protects it with `prevent_destroy`. If the host pool
exists but a fresh Terraform state does not contain it, import it once:

```bash
terraform -chdir=terraform state list
terraform -chdir=terraform import libvirt_pool.default default
```

Do not import again when it is already managed. Match `storage_pool_name` and
`storage_pool_path` to the existing pool before planning. Pool lifecycle startup
is a host prerequisite with this provider version; Terraform manages its definition.

Create and review a private saved plan:

```bash
mkdir -p .local
chmod 700 .local
umask 077
terraform -chdir=terraform plan -out=../.local/lab.tfplan
terraform -chdir=terraform apply ../.local/lab.tfplan
python3 scripts/lab.py check --wait 900
```

Review every delete or replacement. An initial deployment should leave the shared
pool unchanged. Do not use `apply -auto-approve` as a substitute for plan review.
Terraform completing means infrastructure exists; the readiness helper waits for
bootstrap completion, active k3s services, and all expected nodes to be Ready at
the configured addresses.

## Everyday commands

```bash
python3 scripts/lab.py check
python3 scripts/lab.py ssh server
python3 scripts/lab.py kubectl get nodes -o wide
python3 scripts/lab.py kubectl get pods -A
python3 scripts/lab.py smoke
```

The smoke test creates a `homelab-smoke` namespace with two nginx replicas and
checks HTTP through a NodePort at `http://192.168.100.10:30080`. It remains available
for inspection. Remove only the test application with:

```bash
python3 scripts/lab.py kubectl delete namespace homelab-smoke
```

The helper uses your normal SSH identities/agent. For another private key:

```bash
LAB_SSH_KEY=~/.ssh/lab_key python3 scripts/lab.py check
```

SSH host keys are stored separately in `.local/known_hosts`. First contact accepts
and records a new key; changed keys are rejected. After an intentional VM rebuild,
verify the replacement's identity before removing its old host-key entry.

To use a locally installed kubectl:

```bash
python3 scripts/lab.py kubeconfig
export KUBECONFIG="$PWD/.local/kubeconfig"
kubectl get nodes
```

This file grants administrator access. It is stored with mode 0600; do not share
or commit it. Export it again when its embedded certificates need refreshing.
The helper's `kubectl` command avoids a local credential copy altogether.

## Access from another computer

VM addresses are on a private NAT network. They are normally reachable directly
from the virtualization host, not automatically from other devices.

For an SSH session through the host:

```bash
ssh -J your-user@your-host ubuntu@192.168.100.10
```

For the test website, run this on your other computer:

```bash
ssh -N -L 8080:192.168.100.10:30080 your-user@your-host
```

Then visit `http://localhost:8080`. Kubernetes API access similarly needs a route
or tunnel plus matching kubeconfig/certificate settings. No public router ports
or host firewall changes are made by this repository.

## Maintenance and backups

- Keep the host awake and ventilated while the lab is needed. Laptop suspend stops
  its usefulness as a server; inspect your OS power settings deliberately.
- VMs and the lab network are configured to autostart. The existing pool must also
  autostart. Test after a planned host reboot; this is not implied by validation.
- Use `python3 scripts/lab.py check` after maintenance and inspect disk usage before
  growing workloads. Guest disks share the host filesystem.
- Domain configuration updates may stop/start a VM even when Terraform reports an
  in-place change. Schedule downtime and verify live state after applying.
- Cloud-init runs during first boot. Editing its input is **not** an upgrade or a
  reliable reconfiguration mechanism for an already initialized guest.
- The pinned `k3s_version` controls new guests. Upgrade existing guests deliberately,
  server first and then agents, following the matching k3s upgrade documentation.
  Back up first; update the repository pin so future guests match.
- Do not rotate `k3s_token` casually. It is tied to cluster operation and recovery.
- The default Ubuntu URL tracks a release image. Existing volumes are not refreshed
  automatically. Choose a dated image URL when you need identical fresh rebuilds.

Create an on-demand backup:

```bash
python3 scripts/lab.py backup
python3 scripts/lab.py check --wait 120
```

The backup briefly stops the server to archive SQLite consistently, then restarts
it even if archiving fails. It saves the database, server token, k3s configuration,
Terraform state, tfvars, and provider lockfile under `.local/backups/<UTC time>/`.
These archives contain credentials. An `INCOMPLETE` marker means the set failed.

**Copy backups securely off the laptop.** Local backups do not survive loss of the
host. Application persistent-volume data is not included. Back up that data using
application-appropriate methods. Restore guidance and limitations are in `NOTES.md`.

Do not run a blanket `terraform destroy`: the shared pool is protected and contains
unrelated images. Removing the lab requires a reviewed resource-specific plan and
backups. Replacing a guest disk destroys that guest's stored data.

## Troubleshooting

```bash
virsh -c qemu:///system net-dhcp-leases k3s-net
virsh -c qemu:///system console k3s-server
# Exit a virsh console with Ctrl+].
python3 scripts/lab.py ssh server sudo cloud-init status --long
python3 scripts/lab.py ssh server sudo journalctl -u homelab-bootstrap -n 100 --no-pager
python3 scripts/lab.py ssh server sudo journalctl -u k3s -n 100 --no-pager
python3 scripts/lab.py ssh agent-1 sudo journalctl -u k3s-agent -n 100 --no-pager
```

Bootstrap retries failures every 30 seconds. A bootstrap completion marker only
means the installer succeeded; check Kubernetes readiness separately. Review logs
locally before sharing them because bootstrap and service logs may contain secrets.

If the provider reports seed format `iso` versus `raw`, the pool volume must use
`iso`; the VM's QEMU CD-ROM driver still uses `raw`. This configuration accounts
for that distinction.

## Repository map and checks

| Path | Purpose |
|---|---|
| `terraform/main.tf` | Shared pool, Ubuntu base, per-node disks, and NAT network |
| `terraform/variables.tf` | Validated settings and resource budgets |
| `terraform/cloud-init.tf` | Guest login, network, k3s configuration, seed media |
| `terraform/domains.tf` | VM hardware, disk attachments, and autostart |
| `terraform/templates/` | Retryable installer and systemd service |
| `terraform/outputs.tf` | Non-secret node inventory for helper commands |
| `scripts/lab.py` | Readiness, SSH, kubectl, smoke test, credentials, backup |
| `examples/smoke.yaml` | Small removable application used for live verification |
| `tests/` | Checks that readiness rejects unhealthy or misaddressed nodes |
| `terraform/tests/` | Mocked plans checking bootstrap rendering and invalid inputs |
| `NOTES.md` | Design decisions and recovery/maintenance explanations |
| `AGENTS.md` | Instructions for evidence-based agent work in this repository |

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform test
python3 -m unittest discover -s tests -v
```

State, seed media, plans, tfvars, credentials, and backups must stay out of Git.
The provider lockfile and the placeholder-only tfvars example belong in Git.
