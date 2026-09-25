# Repository instructions

## Read before working

- At the start of every task, read this file and any applicable nested
  `AGENTS.md` instructions. Re-read after context loss or changes to instructions.
- Read `README.md`, `NOTES.md`, and the current files relevant to the task before
  proposing or making changes. Inspect `git status --short` to preserve existing work.
- Treat these notes as repository guidance, subject to higher-priority instructions
  and the user's current request. Keep them current when verified project facts change.

## Evidence and honesty

- Never invent facts, files, APIs, command output, test results, or completed work.
  Never knowingly mislead the user or conceal a failure or material limitation.
- Verify factual claims against current files, actual command results, or official
  documentation appropriate to the installed version. Label assumptions and
  inferences; say what is unknown when evidence is unavailable.
- Read actual output and exit status before reporting success. An attempted command
  is not a completed command; an edited configuration is not deployed infrastructure.
- Distinguish intended configuration, recorded Terraform state, and live host
  behavior. None alone proves the others. Do not claim a running cluster without
  appropriate live checks.
- Treat README examples, historical notes, comments, and cached provider examples
  as potentially stale. Resolve contradictions using evidence and tell the user.
- Report what changed, what checks ran and their results, and what remains unverified.
  Correct earlier mistakes directly. Do not describe partial or truncated reads as
  having read everything; disclose skipped files and inaccessible material.

## Project map and observed baseline

Verified from workspace files on 2026-09-24; recheck before relying on this snapshot.

- Goal: a laptop homelab using KVM/QEMU/libvirt and Terraform to provision k3s VMs.
- `terraform/` is the Terraform working directory. `provider.tf` selects
  `qemu:///system`; `versions.tf` requires Terraform `~>1.15` and pins
  `dmacvicar/libvirt` to `0.9.2`, matching `.terraform.lock.hcl`.
- `main.tf` defines an Ubuntu 24.04 base volume, three overlay disks, and a NAT
  network named `k3s-net` using bridge `virbr-k3s` and gateway `192.168.100.1/24`.
  Node reservations are server `.10`, agent-1 `.11`, and agent-2 `.12`.
- `variables.tf` declares the sensitive k3s token and image/storage inputs.
  `per_vm_storage` defaults to 32212254720 bytes (30 GiB), despite its GB wording.
  `main.tf` reads the public key at `~/.ssh/id_ed25519.pub`; verify its availability
  when evaluating configuration without exposing private keys.
- No VM domain resources, cloud-init templates/resources, or outputs currently
  exist in the project source. `NOTES.md` describes some of these as though they
  exist; that text does not establish implementation.
- Local state inspected during this review records `libvirt_pool.default`, while
  current source does not declare that resource. Investigate any proposed removal
  before applying; the state snapshot does not establish live pool status.
- Provider caches include versions other than the pinned version. Their presence
  does not select them. Neither root `.terraform/` nor `terraform/.terraform/`
  is source configuration.
- `.github/workflows/gitleaks.yaml` configures secret scanning for pushes, pull
  requests, and manual runs. Its existence does not prove a successful CI run.

## Working practices

- Make focused changes, preserve unrelated user edits, and explain consequential
  choices in plain language. Update documentation when behavior changes.
- Use `terraform -chdir=terraform ...` from the repository root. Check the actual
  Terraform version and selected provider before relying on their behavior.
- For libvirt attributes, inspect `terraform -chdir=terraform providers schema -json`
  when available and consult official documentation for the pinned version. Do not
  copy legacy provider syntax or newer-version examples without checking compatibility.
- Preserve dependency pins and the committed lockfile unless an upgrade is part of
  the task. Never edit generated caches or state files as a shortcut to fixing source.
- For Terraform changes, run `terraform -chdir=terraform fmt -check -recursive`
  and `terraform -chdir=terraform validate` when prerequisites permit. If initialization
  is needed, preserve the lockfile; do not silently upgrade dependencies. Report
  missing tools, failed initialization, and skipped checks accurately.
- Review an appropriate Terraform plan before an authorized apply, especially
  deletions, replacements, storage changes, and network changes. Formatting and
  validation alone do not prove runtime correctness.
- For documentation-only changes, verify the text against source and review the
  diff/whitespace; infrastructure execution is unnecessary.
- Check actual host capacity, storage pools, and network overlap before provisioning.
  Hardware budgets and network assumptions in the notes are not live measurements.
- Keep infrastructure mutations within the user's authorized scope. Reading or
  documenting the repository does not authorize apply, destroy, state mutation,
  deleting disks, or restarting host services. Do not request approval again for
  actions already authorized; resolve material ambiguity before destructive work.

## Secrets and local artifacts

- Never expose or commit tokens, private keys, kubeconfigs, secret variable files,
  Terraform state/backups, or saved plans. Follow `.gitignore` and inspect diffs for
  accidental secrets. A sensitive variable marker does not make state safe to share.
- Read sensitive local artifacts only as needed; use redacted summaries instead of
  dumping their contents into tool output, documentation, or messages.
- Do not recursively dump `.git`, provider executables, or generated caches during
  routine work. Inventory them when relevant and state the limits of the inspection.
