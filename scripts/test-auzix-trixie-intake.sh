#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${ROOT_DIR}/profiles/packages/auzix-trixie-user-apps.packages"

test -x "${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh"
test -x "${ROOT_DIR}/scripts/run-auzix-trixie-intake.sh"
test -x "${ROOT_DIR}/scripts/run-auzix-office-smoke.sh"
test -x "${ROOT_DIR}/scripts/build-auzix-office-package.sh"
test -x "${ROOT_DIR}/scripts/test-auzix-office-smoke.sh"
test -s "${ROOT_DIR}/docker/trixie-builder/Dockerfile"
grep -F "Description | sed -n '1p'" \
  "${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" >/dev/null
grep -F 'Commands/${command_base}' \
  "${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" >/dev/null
grep -F 'compatibility_exports' \
  "${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" >/dev/null
grep -F 'kind: $kind' \
  "${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" >/dev/null

package_count="$(awk 'NF && $1 !~ /^#/ {print $1}' "${PROFILE}" | sort -u | wc -l)"
(( package_count >= 70 ))
if awk 'NF && $1 !~ /^#/ {print $1}' "${PROFILE}" |
  grep -Evq '^[a-z0-9][a-z0-9+.-]*$'; then
  echo "Trixie profile contains an invalid package name." >&2
  exit 1
fi

echo "AuziX Trixie intake contract: PASS (${package_count} packages)"
