#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
STRACE_VERSION="${AUZIX_STRACE_VERSION:-host}"
STRACE_PROGRAM="${AUZIX_ROOT}/Programs/Strace/${STRACE_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"

log() {
  printf '[auzix-strace] %s\n' "$*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

copy_runtime_deps() {
  local binary="$1"
  local dep
  ldd "${binary}" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' | sort -u |
  while IFS= read -r dep; do
    [[ -e "${dep}" ]] || continue
    case "${dep}" in
      /lib64/*)
        install -D -m 0755 "${dep}" "${RUNTIME_LIB64}/$(basename "${dep}")"
        ;;
      /lib/x86_64-linux-gnu/*|/usr/lib/x86_64-linux-gnu/*)
        install -D -m 0755 "${dep}" "${RUNTIME_LIB}/$(basename "${dep}")"
        ;;
      *)
        install -D -m 0755 "${dep}" "${AUZIX_ROOT}${dep}"
        ;;
    esac
  done
}

copy_binary() {
  local source="$1"
  local target="$2"
  install -D -m 0755 "${source}" "${target}"
  copy_runtime_deps "${source}"
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

require_cmd strace
require_cmd ldd
require_cmd install

mkdir -p \
  "${STRACE_PROGRAM}/Commands" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/PackageDB" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}"

if [[ -e /lib64/ld-linux-x86-64.so.2 ]]; then
  install -D -m 0755 /lib64/ld-linux-x86-64.so.2 "${RUNTIME_LIB64}/ld-linux-x86-64.so.2"
elif [[ -e /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 ]]; then
  install -D -m 0755 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 "${RUNTIME_LIB64}/ld-linux-x86-64.so.2"
fi

copy_binary "$(command -v strace)" "${STRACE_PROGRAM}/Commands/strace"
ln -sfn "/Programs/Strace/${STRACE_VERSION}/Commands/strace" "${AUZIX_ROOT}/System/Compatibility/bin/strace"

cat > "${AUZIX_ROOT}/System/PackageDB/Strace-${STRACE_VERSION}.auzix.json" <<EOF
{
  "name": "Strace",
  "version": "${STRACE_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/Strace/${STRACE_VERSION}",
  "commands": [
    "/Programs/Strace/${STRACE_VERSION}/Commands/strace"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/strace"
  ],
  "notes": "Small diagnostic package. Set AUZIX_TRACE_E=file before /System/Tools/start-e to capture file/process syscalls under /System/Logs/display/strace."
}
EOF

log "strace installed at ${STRACE_PROGRAM}/Commands/strace"
