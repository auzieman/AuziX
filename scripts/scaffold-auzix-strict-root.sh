#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"

log() {
  printf '[auzix-strict] %s\n' "$*" >&2
}

link_compat() {
  local link_path="$1"
  local target="$2"

  if [[ -e "${AUZIX_ROOT}${link_path}" && ! -L "${AUZIX_ROOT}${link_path}" ]]; then
    printf 'Refusing to replace non-symlink: %s\n' "${AUZIX_ROOT}${link_path}" >&2
    exit 1
  fi

  rm -f "${AUZIX_ROOT}${link_path}"
  ln -s "${target}" "${AUZIX_ROOT}${link_path}"
}

log "Creating strict root skeleton at ${AUZIX_ROOT}"

mkdir -p \
  "${AUZIX_ROOT}/System/Boot" \
  "${AUZIX_ROOT}/System/Kernel" \
  "${AUZIX_ROOT}/System/Drivers" \
  "${AUZIX_ROOT}/System/Settings" \
  "${AUZIX_ROOT}/System/State" \
  "${AUZIX_ROOT}/System/State/cache" \
  "${AUZIX_ROOT}/System/State/lib" \
  "${AUZIX_ROOT}/System/State/log" \
  "${AUZIX_ROOT}/System/Logs" \
  "${AUZIX_ROOT}/System/Libraries/Core" \
  "${AUZIX_ROOT}/System/Libraries/Runtime" \
  "${AUZIX_ROOT}/System/Libraries/Drivers" \
  "${AUZIX_ROOT}/System/Libraries/Compatibility" \
  "${AUZIX_ROOT}/System/Tools" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Compatibility/sbin" \
  "${AUZIX_ROOT}/System/Compatibility/lib" \
  "${AUZIX_ROOT}/System/Compatibility/lib64" \
  "${AUZIX_ROOT}/System/Compatibility/usr/bin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/sbin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/lib" \
  "${AUZIX_ROOT}/System/Compatibility/usr/local" \
  "${AUZIX_ROOT}/System/PackageDB" \
  "${AUZIX_ROOT}/System/BuildTools" \
  "${AUZIX_ROOT}/Programs" \
  "${AUZIX_ROOT}/Services" \
  "${AUZIX_ROOT}/Stacks" \
  "${AUZIX_ROOT}/Work/Builds" \
  "${AUZIX_ROOT}/Work/Sources" \
  "${AUZIX_ROOT}/Work/Temp" \
  "${AUZIX_ROOT}/Work/Cache" \
  "${AUZIX_ROOT}/Work/Containers" \
  "${AUZIX_ROOT}/Work/Pipelines" \
  "${AUZIX_ROOT}/Users" \
  "${AUZIX_ROOT}/Users/root" \
  "${AUZIX_ROOT}/Volumes" \
  "${AUZIX_ROOT}/Network/Hosts" \
  "${AUZIX_ROOT}/Network/Interfaces" \
  "${AUZIX_ROOT}/Network/Routes" \
  "${AUZIX_ROOT}/Network/DNS" \
  "${AUZIX_ROOT}/dev" \
  "${AUZIX_ROOT}/proc" \
  "${AUZIX_ROOT}/sys" \
  "${AUZIX_ROOT}/run"

link_compat /bin /System/Compatibility/bin
link_compat /sbin /System/Compatibility/sbin
link_compat /lib /System/Compatibility/lib
link_compat /lib64 /System/Compatibility/lib64
link_compat /usr /System/Compatibility/usr
link_compat /etc /System/Settings
link_compat /var /System/State
link_compat /tmp /Work/Temp
link_compat /opt /Programs
link_compat /home /Users

if [[ -d "${AUZIX_ROOT}/root" && ! -L "${AUZIX_ROOT}/root" ]]; then
  rmdir "${AUZIX_ROOT}/root" 2>/dev/null || {
    printf 'Refusing to replace non-empty root home: %s\n' "${AUZIX_ROOT}/root" >&2
    exit 1
  }
fi
link_compat /root /Users/root
ln -sfn /Work/Temp "${AUZIX_ROOT}/System/State/tmp"
ln -sfn /run "${AUZIX_ROOT}/System/State/run"
ln -sfn /run/lock "${AUZIX_ROOT}/System/State/lock"

cat > "${AUZIX_ROOT}/System/PackageDB/root-layout.auzix.json" <<'JSON'
{
  "name": "AuzixRoot",
  "version": "0.1",
  "contract": "strict-root-prototype",
  "native_top_level": [
    "/System",
    "/Programs",
    "/Services",
    "/Stacks",
    "/Work",
    "/Users",
    "/Volumes",
    "/Network"
  ],
  "linux_runtime": [
    "/dev",
    "/proc",
    "/sys",
    "/run"
  ],
  "compatibility_is_scaffolding": true
}
JSON

log "Strict root skeleton ready"
