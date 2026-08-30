#!/usr/bin/env bash
set -euo pipefail

# Workstation-side helper.
# It starts the strict AUZiX QEMU/SPICE session on lab-build, then opens a local
# SSH tunnel for remote-viewer. It never searches for lab-build artifacts on the
# workstation filesystem.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_CONFIG="${AUZIX_LAB_SSH_CONFIG:-${ROOT_DIR}/../BlackKnightController/ops/workstation-ssh/bkc-lab.conf}"
LAB_HOST="${AUZIX_LAB_HOST:-lab-ai-worker}"
SPICE_PORT="${AUZIX_SPICE_PORT:-5930}"
LOCAL_PORT="${AUZIX_LOCAL_SPICE_PORT:-5930}"
REMOTE_PROJECT="${AUZIX_REMOTE_PROJECT:-/home/auzieman/Projects/AuziX}"

ssh_base=(ssh)
if [[ -f "${SSH_CONFIG}" ]]; then
  ssh_base+=( -F "${SSH_CONFIG}" )
fi
ssh_base+=( "${LAB_HOST}" )

printf 'Starting AUZiX QEMU/SPICE on %s...\n' "${LAB_HOST}" >&2
"${ssh_base[@]}" \
  "set -euo pipefail; cd '${REMOTE_PROJECT}'; AUZIX_QEMU_DETACH=1 AUZIX_SPICE_ADDR=127.0.0.1 AUZIX_SPICE_PORT='${SPICE_PORT}' ./scripts/launch-auzix-strict-spice-qemu.sh; for i in 1 2 3 4 5 6 7 8 9 10; do ss -ltn 2>/dev/null | grep -q ':${SPICE_PORT} ' && exit 0; sleep 1; done; echo 'remote SPICE port ${SPICE_PORT} did not open' >&2; exit 1"

printf 'Opening local tunnel localhost:%s -> %s:127.0.0.1:%s\n' "${LOCAL_PORT}" "${LAB_HOST}" "${SPICE_PORT}" >&2
printf 'Leave this tunnel running, then connect with:\n' >&2
printf '  remote-viewer spice://127.0.0.1:%s\n' "${LOCAL_PORT}" >&2

exec "${ssh_base[@]}" -o ExitOnForwardFailure=yes -N -L "${LOCAL_PORT}:127.0.0.1:${SPICE_PORT}"
