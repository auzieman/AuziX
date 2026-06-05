#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
ALSA_VERSION="${AUZIX_ALSA_VERSION:-host}"
ALSA_PROGRAM="${AUZIX_ROOT}/Programs/ALSA/${ALSA_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"

log() {
  printf '[auzix-alsa] %s\n' "$*" >&2
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

require_cmd aplay
require_cmd speaker-test
require_cmd ldd
require_cmd install

mkdir -p \
  "${ALSA_PROGRAM}/Commands" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/share" \
  "${AUZIX_ROOT}/System/PackageDB" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}"

copy_binary "$(command -v aplay)" "${ALSA_PROGRAM}/Commands/aplay"
copy_binary "$(command -v speaker-test)" "${ALSA_PROGRAM}/Commands/speaker-test"

if [[ -d /usr/share/alsa ]]; then
  rm -rf "${AUZIX_ROOT}/System/Compatibility/usr/share/alsa"
  cp -a /usr/share/alsa "${AUZIX_ROOT}/System/Compatibility/usr/share/alsa"
fi
if [[ -d /usr/share/sounds/alsa ]]; then
  mkdir -p "${AUZIX_ROOT}/System/Compatibility/usr/share/sounds"
  rm -rf "${AUZIX_ROOT}/System/Compatibility/usr/share/sounds/alsa"
  cp -a /usr/share/sounds/alsa "${AUZIX_ROOT}/System/Compatibility/usr/share/sounds/alsa"
fi

ln -sfn "/Programs/ALSA/${ALSA_VERSION}/Commands/aplay" "${AUZIX_ROOT}/System/Compatibility/bin/aplay"
ln -sfn "/Programs/ALSA/${ALSA_VERSION}/Commands/speaker-test" "${AUZIX_ROOT}/System/Compatibility/bin/speaker-test"

cat > "${AUZIX_ROOT}/System/PackageDB/ALSA-${ALSA_VERSION}.auzix.json" <<EOF
{
  "name": "ALSA",
  "version": "${ALSA_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/ALSA/${ALSA_VERSION}",
  "commands": [
    "/Programs/ALSA/${ALSA_VERSION}/Commands/aplay",
    "/Programs/ALSA/${ALSA_VERSION}/Commands/speaker-test"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/aplay",
    "/System/Compatibility/bin/speaker-test"
  ],
  "notes": "Minimal ALSA probe tools for validating /dev/snd before a full audio service exists."
}
EOF

log "ALSA probe tools installed at ${ALSA_PROGRAM}/Commands"
