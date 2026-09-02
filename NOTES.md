# Homelab notes — concepts explained along the way

Personal reference for things that came up while building this project. Not meant to be
polished documentation — just a dump of "what does X mean and why did we do it this way."

---

## 1. The virtualization stack: KVM / QEMU / Libvirt

Three separate layers, stacked bottom to top. None of this is something Terraform
"sets up" — all of it was already installed and enabled on the host before Terraform
ever touched anything.

- **KVM** — a Linux *kernel module*, not a program. Either your CPU/kernel supports
  hardware virtualization and it's enabled, or it isn't. Nothing per-VM about it.
- **QEMU** — the actual program that emulates a VM's virtual hardware (CPU, disk,
  network card). When a VM is running, there's a real `qemu-system-x86_64` process
  on the host for it. QEMU automatically uses KVM under the hood for near-native
  speed instead of full software emulation.
- **Libvirt** — the management layer Terraform actually talks to. It turns our
  declarative resources into libvirt XML, then launches/manages the QEMU process
  for us. The provider config `uri = "qemu:///system"` means "use the QEMU/KVM
  driver, talk to the system-wide libvirtd daemon."

```
Terraform → libvirtd (qemu:///system) → libvirt XML → qemu-system-x86_64 process → KVM acceleration
```

## 2. The Terraform libvirt provider (dmacvicar/libvirt v0.9.2)

This is a **complete rewrite** from older versions (v0.8.x and earlier). It mirrors
raw libvirt XML very closely, so nearly every nested value is an *object*, not a
flat argument — e.g. `backing_store = { path = ..., format = { type = "qcow2" } }`
rather than a flat `format = "qcow2"`. Don't assume older tutorials/examples online
match this syntax — always worth checking the installed schema
(`terraform providers schema -json`) if something looks off.

## 3. Base image + per-node overlay disks

- `libvirt_volume.ubuntu_base` — downloads the Ubuntu 24.04 cloud image **once**.
  A cloud image is a stripped-down, installer-free disk image, built to boot
  instantly — but that means it ships with no user account, password, or SSH
  access configured. (That's what cloud-init is for — see §5.)
- `libvirt_volume.k3s_disk` (×3, `for_each`) — one small **copy-on-write overlay
  disk per VM**, each backed by the shared base image (`backing_store`). Reads
  that haven't changed fall through to the base image; writes go only into the
  VM's own overlay. This is why 3×30GB "capacity" doesn't cost 90GB up front —
  actual usage stays near zero until the guests write data.

## 4. k3s terminology: server vs agent

- **Server** = control-plane node (API server, scheduler, etc. — plus an embedded
  SQLite datastore when there's only 1 server). This is the rendezvous point
  every other node talks to.
- **Agent** = worker node. Runs the kubelet + container runtime, executes actual
  pods, has no control-plane components.

This mirrors real production clusters (cloud-managed or bare-metal) — it's not a
homelab simplification. Every real k8s deployment needs a stable, known address
for its control plane; we're just doing manually (fixed IP, see §6) what cloud
providers automate behind the scenes.

## 5. Networking: why a dedicated `libvirt_network`

- Libvirt ships a `default` NAT network (`192.168.122.0/24`) automatically, for
  any VM that needs generic internet access. We deliberately **don't** use it for
  k3s, because its DHCP range covers the *entire* subnet — no room to safely
  carve out fixed addresses without risking a collision.
- We built `k3s-net` instead: `192.168.100.0/24`, chosen because it's inside the
  RFC 1918 private-address ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`)
  and doesn't collide with anything else already active on the host (`default`
  network, Docker's `172.17.0.0/16`, the host's real Wi-Fi uplink). `/24` is just
  a convention (network = first 3 numbers, host = last number) — no rule forces
  this specific range, only "must be private + must not collide."
- **Static DHCP reservations**: each node has a fixed MAC address
  (`local.k3s_nodes[...].mac`) tied to a fixed IP in the network's `dhcp.hosts`
  list. This solves a chicken-and-egg problem: Terraform has to write the agents'
  "join the server at IP X" instructions *before* anything has booted, so the
  server's IP has to be known in advance. Mechanically: still ordinary DHCP from
  the VM's point of view — it just so happens the host's DHCP server (`dnsmasq`,
  spawned automatically by libvirtd) always hands the same MAC the same address.
  The VM itself never "knows" its IP is fixed.
- The commented-out `ranges` block in `main.tf` is for the *opposite* case: an
  ad-hoc, unreserved VM temporarily attached to this network. Uncommenting it
  gives such a VM a normal (non-fixed, can-change-on-reboot) DHCP lease.

## 6. Cloud-init

Solves the problem in §3: cloud images boot with **no way to log in**. Cloud-init
is a program pre-installed in the image that runs once on first boot and applies
instructions from a small attached virtual CD-ROM (ISO), generated by
`libvirt_cloudinit_disk`. Three files on that ISO:

- **`user-data`** — the actual instructions (create user, install software, run
  commands). This is where our SSH key + k3s install command live.
- **`meta-data`** — small identity info (instance ID, hostname).
- **`network-config`** — how to configure networking (see §7).

## 7. `network_config` / Netplan / why `ethernets:` for a virtual NIC

- Cloud-init doesn't configure networking itself — it hands this block to
  **Netplan**, Ubuntu's standard network config tool, which translates it into
  whatever the OS actually uses under the hood (`systemd-networkd` or
  `NetworkManager`).
- **Why `ethernets:`, not something "virtual"**: "Ethernet" refers to a protocol/
  frame format, not literally "has a physical cable." QEMU emulates a `virtio-net`
  card that behaves exactly like a real Ethernet card from the guest kernel's
  point of view — same driver class, same framing — so it correctly belongs under
  Netplan's `ethernets:` section (as opposed to `wifis:`, which is a genuinely
  different protocol).
- **Why `dhcp4` and not a hardcoded name like `eth0`**: modern Ubuntu cloud images
  (24.04 included) use *predictable* interface names like `enp1s0`, not the old
  `eth0` convention. Our config uses `match: { name: "en*" }` instead of a literal
  interface name, so it works regardless of what the kernel actually calls it.
  `dhcp4: true` means "ask for an IPv4 address via DHCP" (as opposed to hardcoding
  one directly in this file).

## 8. `user-data.tpl` — the `runcmd` install line, decoded

```
curl -sfL https://get.k3s.io | K3S_TOKEN=<token> sh -s - server --write-kubeconfig-mode 644
```

- `curl -sfL <url>` — download k3s's official install script quietly (`-s`), fail
  cleanly on HTTP errors (`-f`), follow redirects (`-L`).
- `| sh -s -` — the classic "curl-pipe-to-shell" install pattern (same one nvm,
  Homebrew, rustup use): feed the downloaded script straight into `sh` instead of
  saving it first. `-s` tells `sh` to read the script from stdin; the `-` marks
  "everything after this is arguments *for the script*, not for `sh`."
- `K3S_TOKEN=<token>` — env var the k3s install script checks; if set, it uses
  this exact value as the join token instead of generating a random one — this is
  how server and agents end up sharing the same secret.
- `server` / `agent` — tells the script which role to install as.
- `K3S_URL=https://<server-ip>:6443` (agents only) — tells the script to join an
  existing server instead of becoming one. Port 6443 is the standard Kubernetes
  API server port.
- `--write-kubeconfig-mode 644` (server only) — loosens permissions on the
  generated kubeconfig (normally root-only) so the `ubuntu` user can run
  `kubectl` without `sudo`. Minor security trade-off, fine for a homelab.

The `%{ if is_server ~} ... %{ else ~} ... %{ endif ~}` around these lines is
**Terraform's** template syntax (not cloud-init's) — resolved by `templatefile()`
before the file is ever written to disk, so each VM only ever sees its own final,
role-specific command.

## 9. The k3s token

A shared secret / "cluster password" — proves a node is authorized to join.
Mechanically, an agent presents it over HTTPS to the server's `:6443` API, and if
it matches, the server issues that agent a signed TLS client certificate it then
uses to authenticate normally. Generated once with:

```bash
openssl rand -hex 32   # 32 random bytes → 64 hex chars → 256 bits of entropy
```

Stored in `terraform/terraform.tfvars` (gitignored, never committed), read via a
`sensitive = true` Terraform variable so it's redacted from `plan`/`apply` output.

## 10. SSH keys, and reaching the VMs

- **SSH key pair**: a *private* key (`~/.ssh/id_ed25519`, never leaves your
  laptop) and a *public* key (`~/.ssh/id_ed25519.pub`, safe to hand out). The
  public key gets installed on a VM ahead of time (via cloud-init); logging in
  later is a cryptographic handshake — the VM never sees or transmits your
  private key, only proof that you hold it. Safer than a password: unguessable,
  never typed, never leaves your machine.
- **Reaching the VMs from anywhere other than this laptop requires a "jump
  host" (double SSH)**: `192.168.100.0/24` is a private virtual network that
  only the laptop itself can reach — like a Docker container's internal IP. From
  another device: `ssh -J you@laptop-ip ubuntu@192.168.100.10` (SSH's built-in
  `-J`/ProxyJump flag chains the two hops into one command), or configure it
  once in `~/.ssh/config` for a short alias.

## 11. Misc / process notes

- The `gitleaks.yaml` CI workflow needed `pull-requests: write` (not `read`) in
  its `permissions:` block — the action tries to leave an inline PR comment on
  findings by default, which needs write access. `contents: read` was already
  correct (checkout is read-only). Scan/fail behavior works either way; only the
  inline PR comment needed the extra permission. Note: GitHub always downgrades
  this token to read-only for PRs coming from a fork, regardless of what's
  configured here — not something we can override.
- `secrets.GITHUB_TOKEN` is auto-generated per workflow run by GitHub Actions —
  never something you create or store yourself in repo secrets. Only needed if
  this were an *org*-owned repo would `GITLEAKS_LICENSE` matter.

---

## Still to do

- `libvirt_domain` resources — the actual VMs, tying disk + cloud-init disk +
  network interface (with matching MAC) + CPU/RAM together.
- Outputs (node IPs) once domains exist.
