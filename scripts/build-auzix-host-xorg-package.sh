#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
XORG_VERSION="${AUZIX_XORG_VERSION:-host}"
XORG_PROGRAM="${AUZIX_ROOT}/Programs/Xorg/${XORG_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"
RUNTIME_USR="${AUZIX_ROOT}/System/Compatibility/usr"
NATIVE_XORG="${AUZIX_ROOT}/System/Drivers/Xorg"
NATIVE_FONTS="${AUZIX_ROOT}/System/Fonts"
NATIVE_X11_SETTINGS="${AUZIX_ROOT}/System/Settings/X11"

log() {
  printf '[auzix-host-xorg] %s\n' "$*" >&2
}

require_path() {
  if [[ ! -e "$1" ]]; then
    printf 'Missing required path: %s\n' "$1" >&2
    exit 1
  fi
}

copy_dep_path() {
  local dep="$1"
  [[ -e "${dep}" ]] || return 0
  case "${dep}" in
    /home/*|/tmp/*|/var/tmp/*)
      return 0
      ;;
    /lib64/*)
      [[ -e "${RUNTIME_LIB64}/$(basename "${dep}")" ]] ||
        install -D -m 0755 "${dep}" "${RUNTIME_LIB64}/$(basename "${dep}")"
      ;;
    /lib/x86_64-linux-gnu/*|/usr/lib/x86_64-linux-gnu/*)
      [[ -e "${RUNTIME_LIB}/$(basename "${dep}")" ]] ||
        install -D -m 0755 "${dep}" "${RUNTIME_LIB}/$(basename "${dep}")"
      ;;
    /usr/lib/*)
      [[ -e "${RUNTIME_USR}/lib/${dep#/usr/lib/}" ]] ||
        install -D -m 0755 "${dep}" "${RUNTIME_USR}/lib/${dep#/usr/lib/}"
      ;;
    *)
      [[ -e "${AUZIX_ROOT}${dep}" ]] ||
        install -D -m 0755 "${dep}" "${AUZIX_ROOT}${dep}"
      ;;
  esac
}

copy_runtime_deps() {
  local binary="$1"
  local dep
  { ldd "${binary}" 2>/dev/null || true; } |
  awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' | sort -u |
  while IFS= read -r dep; do
    copy_dep_path "${dep}"
  done
}

copy_binary() {
  local source="$1"
  local target="$2"
  install -D -m 0755 "${source}" "${target}"
  copy_runtime_deps "${source}"
}

copy_dir_if_present() {
  local source="$1"
  local target="$2"
  [[ -e "${source}" ]] || return 0
  rm -rf "${target}"
  mkdir -p "$(dirname "${target}")"
  cp -a "${source}" "${target}"
}

stage_evdev_driver() {
  local evdev_source="/usr/lib/xorg/modules/input/evdev_drv.so"
  local temp_dir=""

  if [[ ! -e "${evdev_source}" ]]; then
    if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-deb >/dev/null 2>&1; then
      printf 'Missing evdev input driver and cannot fetch it without apt-get/dpkg-deb\n' >&2
      exit 1
    fi
    temp_dir="$(mktemp -d)"
    (
      cd "${temp_dir}"
      apt-get download xserver-xorg-input-evdev >/dev/null
      dpkg-deb -x xserver-xorg-input-evdev_*.deb extract
    )
    evdev_source="${temp_dir}/extract/usr/lib/xorg/modules/input/evdev_drv.so"
  fi

  require_path "${evdev_source}"
  install -D -m 0755 "${evdev_source}" "${RUNTIME_USR}/lib/xorg/modules/input/evdev_drv.so"
  install -D -m 0755 "${evdev_source}" "${NATIVE_XORG}/modules/input/evdev_drv.so"
  copy_runtime_deps "${evdev_source}"

  if [[ -n "${temp_dir}" ]]; then
    copy_dir_if_present "${temp_dir}/extract/usr/share/X11/xorg.conf.d" "${RUNTIME_USR}/share/X11/xorg.conf.d"
    rm -rf "${temp_dir}"
  fi
}

stage_libinput_driver() {
  local libinput_source="/usr/lib/xorg/modules/input/libinput_drv.so"
  local libinput_conf="/usr/share/X11/xorg.conf.d/40-libinput.conf"

  require_path "${libinput_source}"
  require_path "${libinput_conf}"
  install -D -m 0755 "${libinput_source}" "${RUNTIME_USR}/lib/xorg/modules/input/libinput_drv.so"
  install -D -m 0755 "${libinput_source}" "${NATIVE_XORG}/modules/input/libinput_drv.so"
  install -D -m 0644 "${libinput_conf}" "${RUNTIME_USR}/share/X11/xorg.conf.d/40-libinput.conf"
  install -D -m 0644 "${libinput_conf}" "${NATIVE_X11_SETTINGS}/xorg.conf.d/40-libinput.conf"
  copy_dir_if_present /usr/share/libinput "${RUNTIME_USR}/share/libinput"
  copy_runtime_deps "${libinput_source}"
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

require_path /usr/bin/xinit
require_path /usr/bin/Xorg
require_path /usr/bin/xkbcomp
require_path /usr/bin/setxkbmap
require_path /usr/lib/xorg/Xorg
require_path /usr/lib/xorg/Xorg.wrap

mkdir -p \
  "${XORG_PROGRAM}/Commands" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${RUNTIME_USR}/bin" \
  "${RUNTIME_USR}/lib" \
  "${RUNTIME_USR}/share" \
  "${NATIVE_XORG}/modules" \
  "${NATIVE_FONTS}" \
  "${NATIVE_X11_SETTINGS}" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}" \
  "${AUZIX_ROOT}/System/PackageDB"

copy_binary /usr/bin/xinit "${XORG_PROGRAM}/Commands/xinit"
copy_binary /usr/bin/Xorg "${XORG_PROGRAM}/Commands/Xorg"
copy_binary /usr/bin/xkbcomp "${XORG_PROGRAM}/Commands/xkbcomp"
copy_binary /usr/bin/setxkbmap "${XORG_PROGRAM}/Commands/setxkbmap"
copy_binary /usr/lib/xorg/Xorg "${RUNTIME_USR}/lib/xorg/Xorg"
copy_binary /usr/lib/xorg/Xorg.wrap "${RUNTIME_USR}/lib/xorg/Xorg.wrap"
chown root:root "${RUNTIME_USR}/lib/xorg/Xorg.wrap" 2>/dev/null || true
chmod 4755 "${RUNTIME_USR}/lib/xorg/Xorg.wrap" 2>/dev/null || true

copy_dir_if_present /usr/lib/xorg/modules "${RUNTIME_USR}/lib/xorg/modules"
copy_dir_if_present /usr/lib/xorg/modules "${NATIVE_XORG}/modules"
copy_dir_if_present /usr/share/X11/xorg.conf.d "${RUNTIME_USR}/share/X11/xorg.conf.d"
copy_dir_if_present /usr/share/X11/xkb "${RUNTIME_USR}/share/X11/xkb"
copy_dir_if_present /usr/share/X11/xkb "${NATIVE_X11_SETTINGS}/xkb"
copy_dir_if_present /usr/share/fonts/X11 "${RUNTIME_USR}/share/fonts/X11"
copy_dir_if_present /usr/share/fonts/truetype/dejavu "${RUNTIME_USR}/share/fonts/truetype/dejavu"
copy_dir_if_present /usr/share/fonts/X11 "${NATIVE_FONTS}/X11"
copy_dir_if_present /usr/share/fonts/truetype/dejavu "${NATIVE_FONTS}/truetype/dejavu"
stage_libinput_driver
stage_evdev_driver

mkdir -p "${AUZIX_ROOT}/System/Settings/X11" "${AUZIX_ROOT}/System/Settings/X11/xorg.conf.d" "${AUZIX_ROOT}/System/Compatibility/etc/X11"
cat > "${AUZIX_ROOT}/System/Settings/X11/Xwrapper.config" <<'EOF'
allowed_users=anybody
needs_root_rights=yes
EOF
cp "${AUZIX_ROOT}/System/Settings/X11/Xwrapper.config" "${AUZIX_ROOT}/System/Compatibility/etc/X11/Xwrapper.config"

cat > "${AUZIX_ROOT}/System/Settings/X11/xorg.conf" <<'EOF'
Section "Files"
    ModulePath "/System/Drivers/Xorg/modules"
    ModulePath "/System/Compatibility/usr/lib/xorg/modules"
    FontPath "/System/Fonts/X11/misc"
    FontPath "/System/Fonts/X11/Type1"
    FontPath "/System/Fonts/X11/75dpi"
    FontPath "/System/Fonts/X11/100dpi"
    FontPath "/System/Fonts/truetype/dejavu"
EndSection

Section "ServerFlags"
    Option "AutoAddDevices" "true"
    Option "AutoEnableDevices" "true"
    Option "AllowMouseOpenFail" "true"
EndSection

Section "Device"
    Identifier "AuzixVideo"
    Driver "modesetting"
    Option "AccelMethod" "none"
    Option "DRI" "false"
EndSection

Section "Screen"
    Identifier "AuzixScreen"
    Device "AuzixVideo"
EndSection

Section "ServerLayout"
    Identifier "AuzixLayout"
    Screen "AuzixScreen"
EndSection
EOF

find "${RUNTIME_USR}/lib/xorg" "${RUNTIME_LIB}" -type f 2>/dev/null |
while IFS= read -r file_path; do
  if file "${file_path}" | grep -q 'ELF'; then
    copy_runtime_deps "${file_path}" || true
  fi
done

ln -sfn "/Programs/Xorg/${XORG_VERSION}/Commands/xinit" "${AUZIX_ROOT}/System/Compatibility/bin/xinit"
ln -sfn "/Programs/Xorg/${XORG_VERSION}/Commands/Xorg" "${AUZIX_ROOT}/System/Compatibility/bin/Xorg"
ln -sfn "/Programs/Xorg/${XORG_VERSION}/Commands/Xorg" "${AUZIX_ROOT}/System/Compatibility/bin/X"
ln -sfn "/Programs/Xorg/${XORG_VERSION}" "${AUZIX_ROOT}/Programs/Xorg/current"
ln -sfn "/Programs/Xorg/${XORG_VERSION}" "${AUZIX_ROOT}/Programs/Xorg/host"
ln -sfn "/Programs/Xorg/${XORG_VERSION}/Commands/xinit" "${RUNTIME_USR}/bin/xinit"
ln -sfn "/Programs/Xorg/${XORG_VERSION}/Commands/Xorg" "${RUNTIME_USR}/bin/Xorg"
ln -sfn "/Programs/Xorg/${XORG_VERSION}/Commands/Xorg" "${RUNTIME_USR}/bin/X"
ln -sfn "/Programs/Xorg/${XORG_VERSION}/Commands/xkbcomp" "${RUNTIME_USR}/bin/xkbcomp"
ln -sfn "/Programs/Xorg/${XORG_VERSION}/Commands/setxkbmap" "${RUNTIME_USR}/bin/setxkbmap"

cat > "${AUZIX_ROOT}/System/PackageDB/Xorg-${XORG_VERSION}.auzix.json" <<EOF
{
  "name": "Xorg",
  "version": "${XORG_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/Xorg/${XORG_VERSION}",
  "commands": [
    "/Programs/Xorg/${XORG_VERSION}/Commands/Xorg",
    "/Programs/Xorg/${XORG_VERSION}/Commands/xinit",
    "/Programs/Xorg/${XORG_VERSION}/Commands/xkbcomp",
    "/Programs/Xorg/${XORG_VERSION}/Commands/setxkbmap"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/Xorg",
    "/System/Compatibility/bin/X",
    "/System/Compatibility/bin/xinit"
  ],
  "notes": "Host-packaged Xorg proof package for early Enlightenment VM bring-up while native Wayland seat support is under construction."
}
EOF

log "Host Xorg proof package installed at ${XORG_PROGRAM}"
