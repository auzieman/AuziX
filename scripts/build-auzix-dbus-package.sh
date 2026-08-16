#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
DBUS_VERSION="${AUZIX_DBUS_VERSION:-host}"
DBUS_PROGRAM="${AUZIX_ROOT}/Programs/DBus/${DBUS_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"

log() {
  printf '[auzix-dbus] %s\n' "$*" >&2
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

require_cmd dbus-daemon
require_cmd dbus-send
require_cmd ldd
require_cmd install

mkdir -p \
  "${DBUS_PROGRAM}/Commands" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/bin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/share/dbus-1" \
  "${AUZIX_ROOT}/System/Settings/dbus-1" \
  "${AUZIX_ROOT}/System/PackageDB" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}"

copy_binary "$(command -v dbus-daemon)" "${DBUS_PROGRAM}/Commands/dbus-daemon"
copy_binary "$(command -v dbus-send)" "${DBUS_PROGRAM}/Commands/dbus-send"
if command -v dbus-launch >/dev/null 2>&1; then
  copy_binary "$(command -v dbus-launch)" "${DBUS_PROGRAM}/Commands/dbus-launch"
  ln -sfn "/Programs/DBus/${DBUS_VERSION}/Commands/dbus-launch" "${AUZIX_ROOT}/System/Compatibility/bin/dbus-launch"
  ln -sfn "/Programs/DBus/${DBUS_VERSION}/Commands/dbus-launch" "${AUZIX_ROOT}/System/Compatibility/usr/bin/dbus-launch"
fi

ln -sfn "/Programs/DBus/${DBUS_VERSION}/Commands/dbus-daemon" "${AUZIX_ROOT}/System/Compatibility/bin/dbus-daemon"
ln -sfn "/Programs/DBus/${DBUS_VERSION}/Commands/dbus-send" "${AUZIX_ROOT}/System/Compatibility/bin/dbus-send"
ln -sfn "/Programs/DBus/${DBUS_VERSION}/Commands/dbus-daemon" "${AUZIX_ROOT}/System/Compatibility/usr/bin/dbus-daemon"
ln -sfn "/Programs/DBus/${DBUS_VERSION}/Commands/dbus-send" "${AUZIX_ROOT}/System/Compatibility/usr/bin/dbus-send"
if [[ ! -e "${AUZIX_ROOT}/System/Compatibility/bin/which" ]]; then
  ln -sfn "/Programs/BusyBox/1.36.1/Commands/busybox" "${AUZIX_ROOT}/System/Compatibility/bin/which"
fi

for file in /usr/share/dbus-1/session.conf /usr/share/dbus-1/system.conf; do
  [[ -f "${file}" ]] || continue
  install -D -m 0644 "${file}" "${AUZIX_ROOT}/System/Compatibility/usr/share/dbus-1/$(basename "${file}")"
done
for dir in /usr/share/dbus-1/services /usr/share/dbus-1/session.d; do
  [[ -d "${dir}" ]] || continue
  rm -rf "${AUZIX_ROOT}/System/Compatibility/usr/share/dbus-1/$(basename "${dir}")"
  cp -a "${dir}" "${AUZIX_ROOT}/System/Compatibility/usr/share/dbus-1/$(basename "${dir}")"
done

cat > "${AUZIX_ROOT}/System/PackageDB/DBus-${DBUS_VERSION}.auzix.json" <<EOF
{
  "name": "DBus",
  "version": "${DBUS_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/DBus/${DBUS_VERSION}",
  "commands": [
    "/Programs/DBus/${DBUS_VERSION}/Commands/dbus-daemon",
    "/Programs/DBus/${DBUS_VERSION}/Commands/dbus-send",
    "/Programs/DBus/${DBUS_VERSION}/Commands/dbus-launch"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/dbus-daemon",
    "/System/Compatibility/bin/dbus-send",
    "/System/Compatibility/bin/dbus-launch",
    "/System/Compatibility/usr/bin/dbus-daemon",
    "/System/Compatibility/usr/bin/dbus-send",
    "/System/Compatibility/usr/bin/dbus-launch",
    "/System/Compatibility/bin/which"
  ],
  "provides": [
    "dbus-session-bus"
  ],
  "validation": [
    "dbus-daemon --version",
    "dbus-launch --version"
  ],
  "notes": "Minimal DBus system/session bus support for graphical session bring-up. dbus-launch is intentionally exported in both bin and usr/bin because Xsession/enlightenment_start may resolve either path."
}
EOF

log "DBus runtime installed at ${DBUS_PROGRAM}"
