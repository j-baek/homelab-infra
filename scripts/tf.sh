#!/bin/sh
# Keep plans/state private and provider-generated seed media inside a private
# directory. Seed ISOs contain the join token even if Terraform redacts its output.
set -eu
LAB_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
umask 077
mkdir -p "$LAB_ROOT/.local/tmp"
chmod 700 "$LAB_ROOT/.local" "$LAB_ROOT/.local/tmp"
export TMPDIR="$LAB_ROOT/.local/tmp"
exec terraform -chdir="$LAB_ROOT/terraform" "$@"
