#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
ACPID_VERSION="${AUZIX_ACPID_VERSION:-host}"
ACPID_PROGRAM="${AUZIX_ROOT}/Programs/Acpid/${ACPID_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"

log() {
  printf '[auzix-acpid] %s\n' "$*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

copy_dep_path() {
  local dep="$1"
  [[ -e "${dep}" ]] || return 0
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
}

copy_runtime_deps() {
  local binary="$1"
  local dep
  ldd "${binary}" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' | sort -u |
  while IFS= read -r dep; do
    copy_dep_path "${dep}"
  done
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

require_cmd install
require_cmd ldd
ACPID_SOURCE="${AUZIX_ACPID_SOURCE:-/usr/sbin/acpid}"
if [[ ! -x "${ACPID_SOURCE}" ]]; then
  printf 'Missing required acpid binary: %s\n' "${ACPID_SOURCE}" >&2
  exit 1
fi

mkdir -p \
  "${ACPID_PROGRAM}/Commands" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Settings/acpi" \
  "${AUZIX_ROOT}/System/Logs/acpid" \
  "${AUZIX_ROOT}/Services/acpid" \
  "${AUZIX_ROOT}/System/PackageDB" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}"

install -D -m 0755 "${ACPID_SOURCE}" "${ACPID_PROGRAM}/Commands/acpid"
copy_runtime_deps "${ACPID_SOURCE}"
ln -sfn "/Programs/Acpid/${ACPID_VERSION}/Commands/acpid" "${AUZIX_ROOT}/System/Compatibility/bin/acpid"

if [[ -d /etc/acpi ]]; then
  rm -rf "${AUZIX_ROOT}/System/Settings/acpi"
  mkdir -p "${AUZIX_ROOT}/System/Settings"
  cp -a /etc/acpi "${AUZIX_ROOT}/System/Settings/acpi"
fi

cat > "${AUZIX_ROOT}/Services/acpid/run" <<'EOF'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH

BB=/Programs/BusyBox/1.36.1/Commands/busybox
LOG=/System/Logs/acpid/acpid.log
SOCKET=/run/acpid.socket

"${BB}" mkdir -p /System/Logs/acpid /System/State/acpid /run 2>/dev/null || true
if "${BB}" ps | "${BB}" awk '$5 ~ /(^|\/)acpid$/ { found = 1 } END { exit(found ? 0 : 1) }'; then
  exit 0
fi

"${BB}" rm -f "${SOCKET}" /System/State/acpid/socket 2>/dev/null || true
"${BB}" ln -s "${SOCKET}" /System/State/acpid/socket 2>/dev/null || true
echo "starting acpid: $(date 2>/dev/null || true)" >>"${LOG}"
exec acpid -f -n -l -c /System/Settings/acpi/events -s "${SOCKET}" >>"${LOG}" 2>&1
EOF
chmod 0755 "${AUZIX_ROOT}/Services/acpid/run"

cat > "${AUZIX_ROOT}/System/PackageDB/Acpid-${ACPID_VERSION}.auzix.json" <<EOF
{
  "name": "Acpid",
  "version": "${ACPID_VERSION}",
  "kind": "service",
  "prefix": "/Programs/Acpid/${ACPID_VERSION}",
  "commands": [
    "/Programs/Acpid/${ACPID_VERSION}/Commands/acpid"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/acpid"
  ],
  "service": "/Services/acpid",
  "notes": "Small Debian-derived ACPI event daemon service for VM/live desktop parity."
}
EOF

log "Acpid service installed at /Services/acpid/run"
