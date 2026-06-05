#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
SOURCE_PATH="${ROOT_DIR}/sources/auzix-dynprobe/auzix-dynprobe.c"
PROGRAM_ROOT="${AUZIX_ROOT}/Programs/AuzixDynProbe/0.1"
COMMAND_PATH="${PROGRAM_ROOT}/Commands/auzix-dynprobe"
RUNTIME_ROOT="${AUZIX_ROOT}/System/Libraries/Runtime/glibc"
RECEIPT_PATH="${AUZIX_ROOT}/System/PackageDB/AuzixDynProbe-0.1.auzix.json"
BUILD_OUTPUT="${TMPDIR:-/tmp}/auzix-dynprobe.$$"
AUZIX_LOADER="/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2"
AUZIX_RUNPATH="/System/Libraries/Runtime/glibc"

log() {
  printf '[auzix-dynprobe] %s\n' "$*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing. Run scaffold-auzix-strict-root.sh first: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

for cmd in gcc ldd readelf install; do
  require_cmd "${cmd}"
done

mkdir -p \
  "${PROGRAM_ROOT}/Commands" \
  "${PROGRAM_ROOT}/Libraries" \
  "${PROGRAM_ROOT}/Resources" \
  "${RUNTIME_ROOT}" \
  "${AUZIX_ROOT}/System/Logs/auzix-dynprobe" \
  "${AUZIX_ROOT}/System/Compatibility/bin"

log "Building dynamic probe with Auzix interpreter and runpath"
gcc -O2 -o "${BUILD_OUTPUT}" "${SOURCE_PATH}" -lm \
  -Wl,--dynamic-linker="${AUZIX_LOADER}" \
  -Wl,-rpath,"${AUZIX_RUNPATH}"
install -m 0755 "${BUILD_OUTPUT}" "${COMMAND_PATH}"
rm -f "${BUILD_OUTPUT}"

host_loader="$(readelf -l /bin/sh | sed -n 's#.*Requesting program interpreter: \\(.*\\)]#\\1#p' | head -1)"
if [[ -z "${host_loader}" ]]; then
  host_loader="$(gcc -print-file-name=ld-linux-x86-64.so.2)"
fi
if [[ -z "${host_loader}" || ! -e "${host_loader}" ]]; then
  printf 'Could not resolve host dynamic loader from /bin/sh.\n' >&2
  exit 1
fi
install -m 0755 "${host_loader}" "${RUNTIME_ROOT}/ld-linux-x86-64.so.2"

ldd "${COMMAND_PATH}" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' | sort -u |
while IFS= read -r lib_path; do
  [[ -e "${lib_path}" ]] || continue
  install -m 0755 "${lib_path}" "${RUNTIME_ROOT}/$(basename "${lib_path}")"
done

ln -sfn /Programs/AuzixDynProbe/0.1/Commands/auzix-dynprobe \
  "${AUZIX_ROOT}/System/Compatibility/bin/auzix-dynprobe"

cat > "${RECEIPT_PATH}" <<'JSON'
{
  "name": "AuzixDynProbe",
  "version": "0.1",
  "kind": "program",
  "migration_stage": "stage-2-native-paths",
  "prefix": "/Programs/AuzixDynProbe/0.1",
  "commands": [
    "/Programs/AuzixDynProbe/0.1/Commands/auzix-dynprobe"
  ],
  "runtime_libraries": [
    "/System/Libraries/Runtime/glibc"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/auzix-dynprobe"
  ]
}
JSON

log "Dynamic probe interpreter:"
readelf -l "${COMMAND_PATH}" | sed -n '/Requesting program interpreter/p'
log "Dynamic probe dynamic section:"
readelf -d "${COMMAND_PATH}" | grep -E 'NEEDED|RUNPATH|RPATH'

log "AuzixDynProbe installed"
