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

Recheck current source and live results before relying on this snapshot.

- Terraform lives in `terraform/`; the local connection is `qemu:///system`.
  `versions.tf` and the lockfile select libvirt 0.9.2. Do not copy legacy syntax.
- `main.tf` retains the shared `libvirt_pool.default` with `prevent_destroy`,
  provisions an Ubuntu base, per-node qcow2 overlays, and the dedicated NAT network.
  The shared pool contains an unrelated Debian image: preserve it.
- `variables.tf` controls names, subnet, SSH access, version, and per-node budgets.
  Defaults: one 4 GiB server and two 2 GiB agents, each with 2 vCPUs and 30 GiB disk.
- `cloud-init.tf` and `templates/` configure first-boot access and a retryable
  systemd installer. `domains.tf` creates/autostarts the VMs; `outputs.tf` exposes
  non-secret inventory. Seed media and state contain the cluster join secret.
- Cloud-init is initialization, not ongoing guest configuration management.
  A changed template or k3s_version does not upgrade initialized guest disks.
- `scripts/lab.py` provides live readiness, SSH, kubectl, smoke testing, private
  kubeconfig export, and an on-demand SQLite/state backup with brief server downtime.
  `.local/` holds private artifacts. Backups exclude application volume data.
- `examples/smoke.yaml` is a removable nginx deployment and NodePort service.
  `tests/test_lab.py` checks readiness failure cases.
- `README.md` is the operating guide; `NOTES.md` explains design and recovery.
- `.github/workflows/validate.yaml` checks configuration and helper tests;
  `gitleaks.yaml` scans secrets. Configuration is not evidence of a passed CI run.
- During deployment, all three nodes were observed Ready at .10/.11/.12 on
  192.168.100.0/24. Always recheck health; this is not a permanent status guarantee.

## Working practices

- Make focused changes, preserve unrelated user edits, and explain consequential
  choices in plain language. Update documentation when behavior changes.
- Run Terraform directly from the repository root with `terraform -chdir=terraform ...`.
  Check the actual Terraform version and selected provider before relying on their
  behavior. No repository wrapper configures a private temporary directory.
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
