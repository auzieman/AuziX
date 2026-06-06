#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
WORK_DIR="${ROOT_DIR}/out/auzix-packages/iputils"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"

log() {
  printf '[auzix-iputils] %s\n' "$*" >&2
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

  ldd "${binary}" 2>/dev/null |
    awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' |
    sort -u |
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

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

for cmd in apt-cache apt-get dpkg-deb install ldd; do
  require_cmd "${cmd}"
done

IPUTILS_VERSION="${AUZIX_IPUTILS_VERSION:-$(apt-cache show iputils-ping 2>/dev/null | awk '/^Version:/ {print $2; exit}')}"
IPUTILS_VERSION="${IPUTILS_VERSION:-host}"
IPUTILS_PROGRAM="${AUZIX_ROOT}/Programs/IPUtils/${IPUTILS_VERSION}"

rm -rf "${WORK_DIR}" "${IPUTILS_PROGRAM}"
mkdir -p \
  "${WORK_DIR}/debs" \
  "${WORK_DIR}/extract" \
  "${IPUTILS_PROGRAM}/Commands" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/bin" \
  "${AUZIX_ROOT}/System/PackageDB"

(
  cd "${WORK_DIR}/debs"
  apt-get download iputils-ping >/dev/null
)

for deb in "${WORK_DIR}"/debs/*.deb; do
  dpkg-deb -x "${deb}" "${WORK_DIR}/extract"
done

PING_SOURCE="${WORK_DIR}/extract/usr/bin/ping"
if [[ ! -x "${PING_SOURCE}" ]]; then
  PING_SOURCE="${WORK_DIR}/extract/bin/ping"
fi
if [[ ! -x "${PING_SOURCE}" ]]; then
  printf 'iputils ping binary not found in downloaded package.\n' >&2
  exit 1
fi

install -m 0755 "${PING_SOURCE}" "${IPUTILS_PROGRAM}/Commands/ping"
copy_runtime_deps "${PING_SOURCE}"

ln -sfn "/Programs/IPUtils/${IPUTILS_VERSION}" "${AUZIX_ROOT}/Programs/IPUtils/current"
ln -sfn /Programs/IPUtils/current/Commands/ping "${AUZIX_ROOT}/System/Compatibility/bin/ping"
ln -sfn /Programs/IPUtils/current/Commands/ping "${AUZIX_ROOT}/System/Compatibility/usr/bin/ping"
ln -sfn /Programs/IPUtils/current/Commands/ping "${AUZIX_ROOT}/System/Compatibility/bin/ping6"
ln -sfn /Programs/IPUtils/current/Commands/ping "${AUZIX_ROOT}/System/Compatibility/usr/bin/ping6"

cat > "${AUZIX_ROOT}/System/PackageDB/IPUtils-${IPUTILS_VERSION}.auzix.json" <<EOF
{
  "name": "IPUtils",
  "version": "${IPUTILS_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-core-networking",
  "prefix": "/Programs/IPUtils/${IPUTILS_VERSION}",
  "paths": {
    "current": "/Programs/IPUtils/current"
  },
  "commands": [
    "/Programs/IPUtils/${IPUTILS_VERSION}/Commands/ping"
  ],
  "runtime_libraries": [
    "/System/Compatibility/lib/x86_64-linux-gnu"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/ping",
    "/System/Compatibility/bin/ping6",
    "/System/Compatibility/usr/bin/ping",
    "/System/Compatibility/usr/bin/ping6"
  ],
  "notes": "Standalone iputils ping. StartSequence enables the kernel ping socket group range, avoiding setuid on the shared BusyBox multi-call binary."
}
EOF

log "IPUtils installed at ${IPUTILS_PROGRAM}"
