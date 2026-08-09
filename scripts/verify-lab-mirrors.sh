#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_HOST="${AUZIX_LAB_HOST:-lab-ai-worker}"
EXPECTED_COMMIT="${1:-$(cd "${ROOT_DIR}" && git rev-parse --short HEAD)}"
GUIDEBOOK_DIR="${AUZIX_GUIDEBOOK_DIR:-/srv/auzix/guidebooks/vmid132-workstation}"

mirror_paths=(
  /srv/auzix/AuziX/src
  /srv/nfs/swarm/AuziX/src
  /home/admin-deploy/src/AuziX
  /srv/bkc/auzix/src
)

failures=0

for mirror_path in "${mirror_paths[@]}"; do
  if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "${LAB_HOST}" \
    "cd '${mirror_path}' &&
     test \"\$(cat .auzix-commit 2>/dev/null)\" = '${EXPECTED_COMMIT}' &&
     ./scripts/test-auzix-trixie-intake.sh >/tmp/auzix-mirror-test.out &&
     tail -1 /tmp/auzix-mirror-test.out"; then
    printf 'mirror preflight failed: %s:%s expected_commit=%s\n' \
      "${LAB_HOST}" "${mirror_path}" "${EXPECTED_COMMIT}" >&2
    failures=$((failures + 1))
  else
    printf 'mirror ok: %s:%s commit=%s\n' "${LAB_HOST}" "${mirror_path}" "${EXPECTED_COMMIT}"
  fi
done

if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "${LAB_HOST}" \
  "test -s '${GUIDEBOOK_DIR}/apt-manual-packages.txt' &&
   test -s '${GUIDEBOOK_DIR}/dpkg-installed.tsv' &&
   test -s '${GUIDEBOOK_DIR}/tasksel-tasks.txt' &&
   wc -l '${GUIDEBOOK_DIR}/apt-manual-packages.txt' '${GUIDEBOOK_DIR}/dpkg-installed.tsv' '${GUIDEBOOK_DIR}/tasksel-tasks.txt'"; then
  printf 'guidebook preflight failed: %s:%s\n' "${LAB_HOST}" "${GUIDEBOOK_DIR}" >&2
  failures=$((failures + 1))
else
  printf 'guidebook ok: %s:%s\n' "${LAB_HOST}" "${GUIDEBOOK_DIR}"
fi

if (( failures > 0 )); then
  exit 1
fi
