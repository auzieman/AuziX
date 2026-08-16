#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"

detect_host_e_version() {
  local version
  version="$(dpkg-query -W -f='${Version}' enlightenment 2>/dev/null || true)"
  if [[ -n "${version}" ]]; then
    printf '%s\n' "${version}"
    return 0
  fi
  printf 'host\n'
}

E_VERSION="${AUZIX_ENLIGHTENMENT_VERSION:-$(detect_host_e_version)}"
E_PROGRAM="${AUZIX_ROOT}/Programs/Enlightenment/${E_VERSION}"
EFL_PROGRAM="${AUZIX_ROOT}/Programs/EFL/${E_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"
RUNTIME_USR="${AUZIX_ROOT}/System/Compatibility/usr"

log() {
  printf '[auzix-host-e] %s\n' "$*" >&2
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
  if ! file "${binary}" | grep -q 'ELF'; then
    return 0
  fi
  ldd "${binary}" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' | sort -u |
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

copy_lib_glob() {
  local pattern="$1"
  local source
  for source in ${pattern}; do
    [[ -e "${source}" ]] || continue
    cp -a --remove-destination "${source}" "${RUNTIME_LIB}/$(basename "${source}")"
  done
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

require_cmd enlightenment
require_cmd enlightenment_start
require_cmd file
require_cmd ldd
require_cmd install

mkdir -p \
  "${E_PROGRAM}/Commands" \
  "${EFL_PROGRAM}/Commands" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/bin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu" \
  "${AUZIX_ROOT}/System/Compatibility/usr/share" \
  "${AUZIX_ROOT}/System/PackageDB" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}"

copy_binary "$(command -v enlightenment)" "${E_PROGRAM}/Commands/enlightenment"
copy_binary "$(command -v enlightenment_start)" "${E_PROGRAM}/Commands/enlightenment_start"

for cmd in \
  enlightenment_askpass \
  enlightenment_filemanager \
  enlightenment_imc \
  enlightenment_open \
  enlightenment_remote \
  enlightenment_start; do
  path="$(command -v "${cmd}" 2>/dev/null || true)"
  [[ -n "${path}" && -x "${path}" ]] || continue
  copy_binary "${path}" "${E_PROGRAM}/Commands/${cmd}"
done

if [[ -x "${E_PROGRAM}/Commands/enlightenment_remote" ]]; then
  mv "${E_PROGRAM}/Commands/enlightenment_remote" \
    "${E_PROGRAM}/Commands/enlightenment_remote.elive"
  install -m 0755 "${ROOT_DIR}/scripts/enlightenment_remote-auzix" \
    "${E_PROGRAM}/Commands/enlightenment_remote"
fi

for cmd in edje_cc eet evas_cserve2 ecore_evas_convert embryo_cc efreetd; do
  path="$(command -v "${cmd}" 2>/dev/null || true)"
  [[ -n "${path}" && -x "${path}" ]] || continue
  copy_binary "${path}" "${EFL_PROGRAM}/Commands/${cmd}"
done

copy_dir_if_present /usr/lib/x86_64-linux-gnu/efl "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/efl"
copy_dir_if_present /usr/lib/x86_64-linux-gnu/ecore_evas "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/ecore_evas"
copy_dir_if_present /usr/lib/x86_64-linux-gnu/evas "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/evas"
copy_dir_if_present /usr/lib/x86_64-linux-gnu/elementary "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/elementary"
copy_dir_if_present /usr/lib/x86_64-linux-gnu/emotion "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/emotion"
copy_dir_if_present /usr/lib/x86_64-linux-gnu/efreet "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/efreet"
copy_dir_if_present /usr/lib/x86_64-linux-gnu/enlightenment "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment"
for helper in \
  "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_system" \
  "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_ckpasswd"; do
  [[ -e "${helper}" ]] || continue
  chown root:root "${helper}" 2>/dev/null || true
  chmod 4755 "${helper}" 2>/dev/null || true
done
copy_dir_if_present /usr/lib/x86_64-linux-gnu/dri "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/dri"
copy_dir_if_present /usr/share/glvnd "${RUNTIME_USR}/share/glvnd"
copy_lib_glob '/usr/lib/x86_64-linux-gnu/libEGL_mesa.so*'
copy_lib_glob '/usr/lib/x86_64-linux-gnu/libGLdispatch.so*'
copy_lib_glob '/usr/lib/x86_64-linux-gnu/libglapi.so*'
copy_lib_glob '/usr/lib/x86_64-linux-gnu/libOSMesa.so*'
copy_dir_if_present /usr/share/enlightenment "${RUNTIME_USR}/share/enlightenment"
mkdir -p "${RUNTIME_USR}/share/enlightenment/data/backgrounds"
copy_dir_if_present /usr/share/elementary "${RUNTIME_USR}/share/elementary"
copy_dir_if_present /usr/share/efreet "${RUNTIME_USR}/share/efreet"
copy_dir_if_present /usr/share/mime "${RUNTIME_USR}/share/mime"
copy_dir_if_present /usr/share/libinput "${RUNTIME_USR}/share/libinput"
mkdir -p "${RUNTIME_USR}/share/fonts/truetype"
copy_dir_if_present /usr/share/fonts/truetype/dejavu "${RUNTIME_USR}/share/fonts/truetype/dejavu"
copy_dir_if_present /usr/share/X11/xkb "${RUNTIME_USR}/share/X11/xkb"
copy_dir_if_present /etc/fonts "${AUZIX_ROOT}/System/Settings/fonts"

find "${E_PROGRAM}" "${EFL_PROGRAM}" "${RUNTIME_USR}/lib" "${RUNTIME_LIB}" -type f 2>/dev/null |
while IFS= read -r file_path; do
  if file "${file_path}" | grep -q 'ELF'; then
    copy_runtime_deps "${file_path}" || true
  fi
done

ln -sfn "/Programs/Enlightenment/${E_VERSION}/Commands/enlightenment" "${AUZIX_ROOT}/System/Compatibility/bin/enlightenment"
ln -sfn "/Programs/Enlightenment/${E_VERSION}/Commands/enlightenment_start" "${AUZIX_ROOT}/System/Compatibility/bin/enlightenment_start"
rm -rf "${AUZIX_ROOT}/Programs/Enlightenment/current"
rm -rf "${AUZIX_ROOT}/Programs/EFL/current"
ln -sfn "/Programs/Enlightenment/${E_VERSION}" "${AUZIX_ROOT}/Programs/Enlightenment/current"
ln -sfn "/Programs/EFL/${E_VERSION}" "${AUZIX_ROOT}/Programs/EFL/current"
cp -f --remove-destination \
  "${E_PROGRAM}/Commands/enlightenment" \
  "${AUZIX_ROOT}/System/Compatibility/usr/bin/enlightenment"
cp -f --remove-destination \
  "${E_PROGRAM}/Commands/enlightenment_start" \
  "${AUZIX_ROOT}/System/Compatibility/usr/bin/enlightenment_start"
chmod 0755 \
  "${AUZIX_ROOT}/System/Compatibility/usr/bin/enlightenment" \
  "${AUZIX_ROOT}/System/Compatibility/usr/bin/enlightenment_start"

find "${E_PROGRAM}/Commands" -maxdepth 1 -type f -perm -0100 2>/dev/null |
while IFS= read -r cmd_path; do
  cmd_name="$(basename "${cmd_path}")"
  ln -sfn "/Programs/Enlightenment/${E_VERSION}/Commands/${cmd_name}" "${AUZIX_ROOT}/System/Compatibility/bin/${cmd_name}"
  ln -sfn "/Programs/Enlightenment/${E_VERSION}/Commands/${cmd_name}" "${AUZIX_ROOT}/System/Compatibility/usr/bin/${cmd_name}"
done

find "${EFL_PROGRAM}/Commands" -maxdepth 1 -type f -perm -0100 2>/dev/null |
while IFS= read -r cmd_path; do
  cmd_name="$(basename "${cmd_path}")"
  ln -sfn "/Programs/EFL/${E_VERSION}/Commands/${cmd_name}" "${AUZIX_ROOT}/System/Compatibility/bin/${cmd_name}"
  ln -sfn "/Programs/EFL/${E_VERSION}/Commands/${cmd_name}" "${AUZIX_ROOT}/System/Compatibility/usr/bin/${cmd_name}"
done

cat > "${AUZIX_ROOT}/System/PackageDB/Enlightenment-${E_VERSION}.auzix.json" <<EOF
{
  "name": "Enlightenment",
  "version": "${E_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/Enlightenment/${E_VERSION}",
  "depends": [
    "DBus",
    "default-dbus-session-bus",
    "dbus-session-bus"
  ],
  "commands": [
    "/Programs/Enlightenment/${E_VERSION}/Commands/enlightenment",
    "/Programs/Enlightenment/${E_VERSION}/Commands/enlightenment_start"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/enlightenment",
    "/System/Compatibility/bin/enlightenment_start",
    "/System/Compatibility/usr/bin/enlightenment",
    "/System/Compatibility/usr/bin/enlightenment_start"
  ],
  "validation": [
    "enlightenment_start --help",
    "test -x /System/Compatibility/bin/dbus-daemon",
    "test -x /System/Compatibility/bin/dbus-launch || test -S /run/user/1000/bus"
  ],
  "notes": "Host-packaged Enlightenment/EFL proof package. Debian requires default-dbus-session-bus | dbus-session-bus for Enlightenment; AUZiX must provide a runnable session bus path before this package is considered launchable."
}
EOF

log "Host Enlightenment proof package installed at ${E_PROGRAM}"
