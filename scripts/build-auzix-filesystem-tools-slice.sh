#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/extended-ports/AuZiXRoot}"
REPORT_DIR="${ROOT_DIR}/out/source-workbench/extended-ports"

mkdir -p "${AUZIX_ROOT}/System" "${AUZIX_ROOT}/Programs" "${REPORT_DIR}"
rm -rf "${AUZIX_ROOT}/Programs/E2fsprogs" "${AUZIX_ROOT}/Programs/Dosfstools"
find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
  \( -name 'E2fsprogs-*.auzix.json' -o -name 'Dosfstools-*.auzix.json' \) \
  -delete 2>/dev/null || true
"${ROOT_DIR}/scripts/build-auzix-command-suite-package.sh" \
  "${AUZIX_ROOT}" "${ROOT_DIR}/packages/e2fsprogs.command-suite.json"
"${ROOT_DIR}/scripts/build-auzix-command-suite-package.sh" \
  "${AUZIX_ROOT}" "${ROOT_DIR}/packages/dosfstools.command-suite.json"

mapfile -t receipts < <(find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
  \( -name 'E2fsprogs-*.auzix.json' -o -name 'Dosfstools-*.auzix.json' \) | sort)
[[ "${#receipts[@]}" -eq 2 ]]

jq -n \
  --arg format "auzix-extended-port-slice-v1" \
  --arg status "passed" \
  --arg root "${AUZIX_ROOT}" \
  --slurpfile e2fs "${receipts[1]}" \
  --slurpfile dosfs "${receipts[0]}" \
  '{format: $format, status: $status, root: $root, packages: [$e2fs[0], $dosfs[0]]}' \
  >"${REPORT_DIR}/filesystem-tools.report.json"
