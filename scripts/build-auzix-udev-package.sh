#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
UDEV_VERSION="${AUZIX_UDEV_VERSION:-host}"
UDEV_PROGRAM="${AUZIX_ROOT}/Programs/Udev/${UDEV_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"

log() {
  printf '[auzix-udev] %s\n' "$*" >&2
}

copy_dep_path() {
  local dep="$1"
  [[ -e "${dep}" ]] || return 0
  case "${dep}" in
    /lib64/*)
      install -D -m 0755 "${dep}" "${RUNTIME_LIB64}/$(basename "${dep}")"
      ;;
    /usr/lib64/*)
      install -D -m 0755 "${dep}" "${AUZIX_ROOT}/System/Compatibility${dep}"
      ;;
    /lib/x86_64-linux-gnu/*|/usr/lib/x86_64-linux-gnu/*)
      install -D -m 0755 "${dep}" "${RUNTIME_LIB}/$(basename "${dep}")"
      ;;
    /usr/*)
      install -D -m 0755 "${dep}" "${AUZIX_ROOT}/System/Compatibility${dep}"
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

copy_dir_if_present() {
  local source="$1"
  local target="$2"
  [[ -e "${source}" ]] || return 0
  rm -rf "${target}"
  mkdir -p "$(dirname "${target}")"
  mkdir -p "${target}"
  while IFS= read -r item; do
    local rel="${item#${source}/}"
    if [[ -d "${item}" ]]; then
      mkdir -p "${target}/${rel}"
    elif [[ -r "${item}" ]]; then
      install -D -m 0644 "${item}" "${target}/${rel}"
    else
      log "skipping unreadable udev asset: ${item}"
    fi
  done < <(find "${source}" -mindepth 1 -print)
}

force_symlink() {
  local source="$1"
  local target="$2"
  mkdir -p "$(dirname "${target}")"
  rm -f "${target}"
  ln -s "${source}" "${target}"
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

UDEVADM_SOURCE="${AUZIX_UDEVADM_SOURCE:-/bin/udevadm}"
if [[ ! -x "${UDEVADM_SOURCE}" ]]; then
  UDEVADM_SOURCE=/usr/bin/udevadm
fi
if [[ ! -x "${UDEVADM_SOURCE}" ]]; then
  printf 'Missing required udevadm binary\n' >&2
  exit 1
fi

mkdir -p \
  "${UDEV_PROGRAM}/Commands" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Compatibility/lib/systemd" \
  "${AUZIX_ROOT}/System/Compatibility/lib/udev" \
  "${AUZIX_ROOT}/System/Compatibility/usr/lib/systemd" \
  "${AUZIX_ROOT}/System/Compatibility/usr/lib/udev" \
  "${AUZIX_ROOT}/System/Logs/udev" \
  "${AUZIX_ROOT}/Services/udev" \
  "${AUZIX_ROOT}/System/PackageDB" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}"

install -D -m 0755 "${UDEVADM_SOURCE}" "${UDEV_PROGRAM}/Commands/udevadm"
copy_runtime_deps "${UDEVADM_SOURCE}"

force_symlink "/Programs/Udev/${UDEV_VERSION}/Commands/udevadm" "${AUZIX_ROOT}/System/Compatibility/bin/udevadm"
force_symlink "/Programs/Udev/${UDEV_VERSION}/Commands/udevadm" "${AUZIX_ROOT}/System/Compatibility/lib/systemd/systemd-udevd"
force_symlink "/Programs/Udev/${UDEV_VERSION}/Commands/udevadm" "${AUZIX_ROOT}/System/Compatibility/usr/bin/udevadm"
force_symlink "/Programs/Udev/${UDEV_VERSION}/Commands/udevadm" "${AUZIX_ROOT}/System/Compatibility/usr/lib/systemd/systemd-udevd"

copy_dir_if_present /lib/udev/rules.d "${AUZIX_ROOT}/System/Compatibility/lib/udev/rules.d"
copy_dir_if_present /lib/udev/hwdb.d "${AUZIX_ROOT}/System/Compatibility/lib/udev/hwdb.d"
if [[ -f /lib/udev/hwdb.bin ]]; then
  install -D -m 0644 /lib/udev/hwdb.bin "${AUZIX_ROOT}/System/Compatibility/lib/udev/hwdb.bin"
fi
for helper in /lib/udev/*; do
  [[ -f "${helper}" && -x "${helper}" ]] || continue
  install -D -m 0755 "${helper}" "${AUZIX_ROOT}/System/Compatibility/lib/udev/$(basename "${helper}")"
  copy_runtime_deps "${helper}" || true
done

# Debian Trixie moved the real udev payload under /usr/lib/udev.  Xorg/libinput
# needs rules such as 60-input-id.rules plus the input_id builtin/helper and
# hwdb to tag /dev/input/event* with ID_INPUT*.  Copy both historical and modern
# locations so AUZiX does not silently lose mouse/keyboard discovery.
copy_dir_if_present /usr/lib/udev/rules.d "${AUZIX_ROOT}/System/Compatibility/usr/lib/udev/rules.d"
copy_dir_if_present /usr/lib/udev/hwdb.d "${AUZIX_ROOT}/System/Compatibility/usr/lib/udev/hwdb.d"
if [[ -f /usr/lib/udev/hwdb.bin ]]; then
  install -D -m 0644 /usr/lib/udev/hwdb.bin "${AUZIX_ROOT}/System/Compatibility/usr/lib/udev/hwdb.bin"
fi
for helper in /usr/lib/udev/*; do
  [[ -f "${helper}" && -x "${helper}" ]] || continue
  install -D -m 0755 "${helper}" "${AUZIX_ROOT}/System/Compatibility/usr/lib/udev/$(basename "${helper}")"
  copy_runtime_deps "${helper}" || true
done

cat > "${AUZIX_ROOT}/Services/udev/run" <<'EOF'
#!/System/Compatibility/bin/sh
set -u

PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH

BB=/Programs/BusyBox/1.36.1/Commands/busybox
LOG=/System/Logs/udev/udev.log
UDEVD=/System/Compatibility/lib/systemd/systemd-udevd

"${BB}" mkdir -p /System/Logs/udev /run/udev /run/udev/data 2>/dev/null || true

if ! "${BB}" ps | "${BB}" grep '[s]ystemd-udevd' >/dev/null 2>&1; then
  "${UDEVD}" --daemon >>"${LOG}" 2>&1 || true
fi

udevadm trigger --type=subsystems --action=add >>"${LOG}" 2>&1 || true
udevadm trigger --type=devices --action=add >>"${LOG}" 2>&1 || true
udevadm settle --timeout=10 >>"${LOG}" 2>&1 || true
exit 0
EOF
chmod 0755 "${AUZIX_ROOT}/Services/udev/run"

cat > "${AUZIX_ROOT}/System/PackageDB/Udev-${UDEV_VERSION}.auzix.json" <<EOF
{
  "name": "Udev",
  "version": "${UDEV_VERSION}",
  "kind": "service",
  "prefix": "/Programs/Udev/${UDEV_VERSION}",
  "commands": [
    "/Programs/Udev/${UDEV_VERSION}/Commands/udevadm"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/udevadm",
    "/System/Compatibility/lib/systemd/systemd-udevd"
  ],
  "service": "/Services/udev",
  "notes": "Minimal Debian udev runtime for Xorg/libinput device discovery."
}
EOF

log "Udev service installed at /Services/udev/run"
