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

## Storage ownership and data preservation

The existing `default` directory pool remains at `libvirt_pool.default`. This
resolves the earlier mismatch where state managed the pool but configuration did
not declare it. `prevent_destroy` blocks replacement/deletion while this resource
is declared. It does not protect against removing the resource block or manually
deleting files. Never treat it as a backup.

The pool contains an unrelated Debian cloud image. Lab resources do not manage
that image. New guests use a shared Ubuntu base with independent qcow2 overlays.
The base remains necessary for every overlay; copying an overlay alone is not a
complete disk backup. Use a deliberate flatten/export process or preserve the
whole backing chain when doing disk-level backups.

Capacity inputs use GiB; the provider receives bytes. RAM inputs use MiB. Virtual
capacity does not reserve that much physical space immediately. Monitor actual
host free space as guests grow.

Seed media contains the join token and public-key configuration. The provider
builds a local ISO, then a libvirt volume uploads it to the pool. Pool seed files
use restricted permissions. The provider itself creates temporary ISO files with
mode 0644 in the environment's temporary directory. Terraform is run directly;
the repository does not configure a private temporary directory. Terraform state
and plan files also contain secrets, even when CLI output marks values sensitive.

Planned follow-up: move token storage and retrieval from local tfvars to HashiCorp
Vault or another secrets manager. This is not implemented yet. The migration must
also address how the token reaches guests; changing its source alone does not
remove copies from Terraform state or seed media.

## Networking

Each guest receives a DHCP lease reserved by its configured MAC address. Guest
cloud-init matches that MAC and renames the NIC to `eth0`; k3s uses the same NIC
for Flannel. The default node addresses are .10, .11, and .12; .1 is the gateway.

NAT provides outbound access. It does not automatically expose the VMs to every
computer on your LAN. SSH jump connections and tunnels are practical access paths.
A dedicated network gives this lab explicit ownership and predictable addresses;
it is not because libvirt's default network inherently cannot support reservations.

Before changing subnets, check the host, LAN, VPN, and Kubernetes pod/service
networks. Changing IPs in Terraform alone does not reliably rewrite configuration
inside existing guests. Treat such a change as a planned migration/rebuild.

## First boot and retries

Cloud-init configures a non-root, key-only SSH administrator with passwordless
sudo and writes a root-only `/etc/rancher/k3s/config.yaml`. YAML encoding preserves
literal token values without placing them in shell command arguments.

Cloud-init starts `homelab-bootstrap.service` without blocking its own completion.
The unit waits for cloud-final and network-online, installs the pinned k3s release,
and retries failures after 30 seconds. Agents can start before the server; their
k3s service handles joining as the server becomes available.

`/var/lib/homelab/bootstrap-complete` means the install script succeeded. It does
not mean every Kubernetes component or application is ready. `lab.py check`
verifies installation markers, services, exact node membership, Ready conditions,
and expected InternalIP addresses. It lists system pods for inspection; it does
not claim that every listed pod is healthy.

Cloud-init is initialization, not ongoing configuration management. A changed seed
may be replaced in Terraform, but an initialized disk normally keeps its original
instance setup. Do not expect changing a template to upgrade k3s or rotate keys on
an existing guest. Review seed replacements carefully when VMs are running.

## Administrator access

The guest administrator can become root via sudo. Protect its private SSH key.
The kubeconfig copied by `lab.py kubeconfig` has full cluster administrator rights
and mode 0600. Prefer `lab.py kubectl` when no local copy is needed.

The helper stores first-contact SSH host keys in `.local/known_hosts` using
`accept-new`, never `StrictHostKeyChecking=no`. First contact is trust-on-first-use;
for stronger assurance compare fingerprints through a trusted guest console.
An unexpected changed key is a reason to investigate, not disable checking.

## Updates

Before updating: create a backup, check node health, and read the release's upgrade
notes. Keep the three nodes on compatible versions. Upgrade the server before
agents, verify each step, and update `k3s_version` for subsequent guest creation.
Do not skip Kubernetes minor-version upgrade constraints.

The bootstrap script can be inspected on each guest, but its completion marker
intentionally prevents automatic reruns. Perform upgrades as explicit operations,
not by deleting markers blindly. OS package maintenance and reboots are also
explicit; do not assume Terraform performs them.

## Backup and recovery

The single-server default uses SQLite. `lab.py backup` stops k3s briefly, archives
its database directory and server token alongside configuration, then restarts it.
The same set includes host Terraform state, tfvars, and the provider lockfile.
Do not apply Terraform concurrently with a backup. The command does not back up
application volume contents or every guest disk.

Recovery requires both the database and matching token. Preserve the exact k3s
version, restore onto a compatible server with k3s stopped, restore the database,
token, and configuration with their ownership/permissions, then start and verify.
If replacing the host, restore Terraform state only after checking that its paths,
resource identities, and actual infrastructure match; state cannot recreate lost
application data by itself. Never blindly apply stale state to an unrelated host.

A practical recovery drill should use an isolated copy, confirm server health,
rejoin/reconcile agents as necessary, and verify application data separately.
The existence of an archive is not proof of a tested restore. Off-host copies and
application-specific backups are needed before treating the lab as durable storage.

## Provider and validation lessons

The installed provider schema is the authority for supported attributes. Legacy
libvirt examples often use incompatible nesting. Check it with:

```bash
terraform -chdir=terraform providers schema -json
```

The pool reports uploaded CD-ROM media as `iso`, while QEMU reads the attached
CD-ROM using a `raw` driver. Requesting `raw` for the pool volume produced an
inconsistent-result error during the first deployment; configuration now uses
`iso` for that volume.

The console definition intentionally leaves its source unspecified so libvirt can
allocate the pseudo-terminal. Configuring an empty PTY path produced an inconsistent
result after creation. Updating VM configuration with provider 0.9.2 also restarted
guests and exposed a runtime domain-ID inconsistency. The guests were checked live,
failed-create markers cleared only after verification, and state reconciled with
a fresh plan. Do not blindly repeat failed applies or untaint unverified resources.
Expect possible downtime even when a plan calls a domain change an in-place update.

Formatting checks style; validation checks Terraform configuration; a plan checks
proposed changes against refreshed resource state. None verifies guest bootstrap,
SSH access, Kubernetes readiness, or application traffic. Those need live checks.

## Primary references

- [k3s installation configuration](https://docs.k3s.io/installation/configuration)
- [k3s cluster access](https://docs.k3s.io/cluster-access)
- [k3s backup and restore](https://docs.k3s.io/datastore/backup-restore)
- [k3s manual upgrades](https://docs.k3s.io/upgrades/manual)
- [cloud-init users and groups](https://cloudinit.readthedocs.io/en/stable/reference/yaml_examples/user_groups.html)
- [libvirt provider 0.9.2](https://registry.terraform.io/providers/dmacvicar/libvirt/0.9.2/docs)

## Verification during implementation

On 2026-09-24 (host-local date), all three guests were observed Ready on the pinned
k3s version. The test deployment ran across two nodes and its HTTP NodePort
responded from the host. A subsequent Terraform plan reported no changes, and a
no-change apply succeeded. Configuration validation, three mocked Terraform tests,
and four readiness-helper tests passed locally.

An on-demand backup completed, its archives contained the expected files, and
SQLite `PRAGMA integrity_check` returned `ok` on a private extracted copy. The
cluster recovered after VM restarts and the backup's brief k3s restart. A complete
restore onto a replacement host and a physical-host reboot have not been tested.
GitHub CI is configured but has not been run as part of this local work. Backups
are currently local; no off-host destination has been configured.
