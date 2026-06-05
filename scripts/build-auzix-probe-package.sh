#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
SOURCE_PATH="${ROOT_DIR}/sources/auzix-probe/auzix-probe.c"
PROGRAM_ROOT="${AUZIX_ROOT}/Programs/AuzixProbe/0.1"
COMMAND_PATH="${PROGRAM_ROOT}/Commands/auzix-probe"
RECEIPT_PATH="${AUZIX_ROOT}/System/PackageDB/AuzixProbe-0.1.auzix.json"
BUILD_OUTPUT="${TMPDIR:-/tmp}/auzix-probe.$$"

log() {
  printf '[auzix-probe] %s\n' "$*" >&2
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing. Run scaffold-auzix-strict-root.sh first: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

if [[ ! -f "${SOURCE_PATH}" ]]; then
  printf 'Source file not found: %s\n' "${SOURCE_PATH}" >&2
  exit 1
fi

if ! command -v gcc >/dev/null 2>&1; then
  printf 'gcc is required to build AuzixProbe.\n' >&2
  exit 1
fi

log "Installing AuzixProbe into ${PROGRAM_ROOT}"
mkdir -p \
  "${PROGRAM_ROOT}/Commands" \
  "${PROGRAM_ROOT}/Libraries" \
  "${PROGRAM_ROOT}/Resources" \
  "${AUZIX_ROOT}/System/Settings/auzix-probe" \
  "${AUZIX_ROOT}/System/State/auzix-probe" \
  "${AUZIX_ROOT}/System/Logs/auzix-probe" \
  "${AUZIX_ROOT}/System/Compatibility/bin"

if gcc -static -Os -s -o "${BUILD_OUTPUT}" "${SOURCE_PATH}"; then
  log "Built static probe binary"
else
  log "Static build failed; building dynamic probe so the audit can show linker debt"
  gcc -Os -s -o "${BUILD_OUTPUT}" "${SOURCE_PATH}"
fi
install -m 0755 "${BUILD_OUTPUT}" "${COMMAND_PATH}"
rm -f "${BUILD_OUTPUT}"

ln -sfn /Programs/AuzixProbe/0.1/Commands/auzix-probe \
  "${AUZIX_ROOT}/System/Compatibility/bin/auzix-probe"

cat > "${RECEIPT_PATH}" <<'JSON'
{
  "name": "AuzixProbe",
  "version": "0.1",
  "kind": "program",
  "migration_stage": "stage-2-native-paths",
  "prefix": "/Programs/AuzixProbe/0.1",
  "commands": [
    "/Programs/AuzixProbe/0.1/Commands/auzix-probe"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/auzix-probe"
  ]
}
JSON

"${COMMAND_PATH}" > "${AUZIX_ROOT}/System/Logs/auzix-probe/install-check.log"
file "${COMMAND_PATH}"
if command -v readelf >/dev/null 2>&1; then
  readelf -h "${COMMAND_PATH}" | sed -n '1,12p'
fi

log "AuzixProbe installed"
