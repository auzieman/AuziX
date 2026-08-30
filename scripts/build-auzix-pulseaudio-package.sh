#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
PULSE_VERSION="${AUZIX_PULSE_VERSION:-host}"
PULSE_PROGRAM="${AUZIX_ROOT}/Programs/PulseAudio/${PULSE_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"
RUNTIME_USR="${AUZIX_ROOT}/System/Compatibility/usr"

log() {
  printf '[auzix-pulseaudio] %s\n' "$*" >&2
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
    /usr/lib/*)
      install -D -m 0755 "${dep}" "${RUNTIME_USR}/lib/${dep#/usr/lib/}"
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

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

require_cmd pulseaudio
require_cmd pactl
require_cmd file
require_cmd install
require_cmd ldd

mkdir -p \
  "${PULSE_PROGRAM}/Commands" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${RUNTIME_USR}/bin" \
  "${RUNTIME_USR}/lib" \
  "${RUNTIME_USR}/share" \
  "${AUZIX_ROOT}/System/Settings" \
  "${AUZIX_ROOT}/System/Logs/pulseaudio" \
  "${AUZIX_ROOT}/System/PackageDB" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}"

copy_binary "$(command -v pulseaudio)" "${PULSE_PROGRAM}/Commands/pulseaudio"
copy_binary "$(command -v pactl)" "${PULSE_PROGRAM}/Commands/pactl"

for pulse_lib_dir in /usr/lib/pulse-*; do
  [[ -d "${pulse_lib_dir}" ]] || continue
  copy_dir_if_present "${pulse_lib_dir}" "${RUNTIME_USR}/lib/$(basename "${pulse_lib_dir}")"
done
copy_dir_if_present /usr/lib/x86_64-linux-gnu/pulseaudio "${RUNTIME_USR}/lib/x86_64-linux-gnu/pulseaudio"
copy_dir_if_present /usr/share/pulseaudio "${RUNTIME_USR}/share/pulseaudio"
copy_dir_if_present /usr/share/alsa "${RUNTIME_USR}/share/alsa"
copy_dir_if_present /usr/share/alsa-card-profile "${RUNTIME_USR}/share/alsa-card-profile"
copy_dir_if_present /etc/pulse "${AUZIX_ROOT}/System/Settings/pulse"

for runtime_pulse_dir in "${RUNTIME_USR}"/lib/pulse-* "${RUNTIME_USR}/lib/x86_64-linux-gnu/pulseaudio"; do
  [[ -d "${runtime_pulse_dir}" ]] || continue
  find "${runtime_pulse_dir}" -type f 2>/dev/null |
  while IFS= read -r file_path; do
    if file "${file_path}" | grep -q 'ELF'; then
      copy_runtime_deps "${file_path}" || true
    fi
  done
done

ln -sfn "/Programs/PulseAudio/${PULSE_VERSION}/Commands/pulseaudio" "${AUZIX_ROOT}/System/Compatibility/bin/pulseaudio"
ln -sfn "/Programs/PulseAudio/${PULSE_VERSION}/Commands/pactl" "${AUZIX_ROOT}/System/Compatibility/bin/pactl"
ln -sfn "/Programs/PulseAudio/${PULSE_VERSION}/Commands/pulseaudio" "${RUNTIME_USR}/bin/pulseaudio"
ln -sfn "/Programs/PulseAudio/${PULSE_VERSION}/Commands/pactl" "${RUNTIME_USR}/bin/pactl"

cat > "${AUZIX_ROOT}/System/PackageDB/PulseAudio-${PULSE_VERSION}.auzix.json" <<EOF
{
  "name": "PulseAudio",
  "version": "${PULSE_VERSION}",
  "kind": "program",
  "prefix": "/Programs/PulseAudio/${PULSE_VERSION}",
  "commands": [
    "/Programs/PulseAudio/${PULSE_VERSION}/Commands/pulseaudio",
    "/Programs/PulseAudio/${PULSE_VERSION}/Commands/pactl"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/pulseaudio",
    "/System/Compatibility/bin/pactl"
  ],
  "notes": "Minimal Debian PulseAudio user-session runtime for Enlightenment mixer compatibility."
}
EOF

log "PulseAudio runtime installed at ${PULSE_PROGRAM}"
