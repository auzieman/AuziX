#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
TERM_VERSION="${AUZIX_TERMINOLOGY_VERSION:-host}"
TERM_PROGRAM="${AUZIX_ROOT}/Programs/Terminology/${TERM_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"
RUNTIME_USR="${AUZIX_ROOT}/System/Compatibility/usr"

log() {
  printf '[auzix-terminology] %s\n' "$*" >&2
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

require_cmd terminology
require_cmd file
require_cmd install
require_cmd ldd

mkdir -p \
  "${TERM_PROGRAM}/Commands" \
  "${TERM_PROGRAM}/Libexec" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${RUNTIME_USR}/bin" \
  "${RUNTIME_USR}/share/applications" \
  "${RUNTIME_USR}/share/icons" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}" \
  "${AUZIX_ROOT}/System/PackageDB"

for cmd in terminology tyalpha tybg tycat tyls typop tyq tysend; do
  path="$(command -v "${cmd}" 2>/dev/null || true)"
  [[ -n "${path}" && -x "${path}" ]] || continue
  copy_binary "${path}" "${TERM_PROGRAM}/Commands/${cmd}"
  ln -sfn "/Programs/Terminology/${TERM_VERSION}/Commands/${cmd}" "${AUZIX_ROOT}/System/Compatibility/bin/${cmd}"
  ln -sfn "/Programs/Terminology/${TERM_VERSION}/Commands/${cmd}" "${RUNTIME_USR}/bin/${cmd}"
done

ln -sfn "/Programs/Terminology/${TERM_VERSION}" "${AUZIX_ROOT}/Programs/Terminology/current"

if [[ -x /usr/libexec/x86_64-linux-gnu/terminology/tytest ]]; then
  copy_binary /usr/libexec/x86_64-linux-gnu/terminology/tytest "${TERM_PROGRAM}/Libexec/tytest"
  install -D -m 0755 /usr/libexec/x86_64-linux-gnu/terminology/tytest \
    "${RUNTIME_USR}/libexec/x86_64-linux-gnu/terminology/tytest"
fi

copy_dir_if_present /usr/share/terminology "${RUNTIME_USR}/share/terminology"
if [[ -f /usr/share/applications/terminology.desktop ]]; then
  install -D -m 0644 /usr/share/applications/terminology.desktop \
    "${RUNTIME_USR}/share/applications/terminology.desktop"
fi
cat > "${RUNTIME_USR}/share/applications/auzix-terminal.desktop" <<'EOF_DESKTOP'
[Desktop Entry]
Type=Application
Name=Auzix Terminal
Comment=Open a local Auzix shell
TryExec=terminology
Exec=/System/Tools/launch-auzix-terminal
Icon=utilities-terminal
Categories=System;TerminalEmulator;
Terminal=false
StartupWMClass=terminology
EOF_DESKTOP
copy_dir_if_present /usr/share/icons/hicolor "${RUNTIME_USR}/share/icons/hicolor"

find "${TERM_PROGRAM}" "${RUNTIME_USR}/share/terminology" -type f 2>/dev/null |
while IFS= read -r file_path; do
  if file "${file_path}" | grep -q 'ELF'; then
    copy_runtime_deps "${file_path}" || true
  fi
done

mkdir -p "${AUZIX_ROOT}/System/Tools"
cat > "${AUZIX_ROOT}/System/Tools/launch-auzix-terminal" <<'EOF'
#!/System/Compatibility/bin/sh
set -eu

if [ -r /System/Settings/auzix-paths.sh ]; then
  . /System/Settings/auzix-paths.sh
fi

export PATH="/Programs/Terminology/current/Commands:/Programs/XTerm/current/Commands:/System/Compatibility/bin:/System/Compatibility/usr/bin:/Programs/BusyBox/current/Commands:${PATH:-}"
export HOME="${HOME:-/Users/auzix}"
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/System/Compatibility/usr/local/share:/System/Compatibility/usr/share:/Programs/Enlightenment/host/Resources/share:/Programs/EFL/host/Resources/share}"
export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/System/Settings/xdg:/System/Compatibility/etc/xdg}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64:/System/Libraries}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
export CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-${SSL_CERT_FILE}}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export ELM_ACCEL="${ELM_ACCEL:-none}"
export ECORE_EVAS_ENGINE="${ECORE_EVAS_ENGINE:-software_x11}"
export ELM_ENGINE="${ELM_ENGINE:-software_x11}"
export E_COMP_ENGINE="${E_COMP_ENGINE:-sw}"

if command -v terminology >/dev/null 2>&1; then
  exec terminology -e /System/Compatibility/bin/bash "$@"
fi

exec xterm -T "AUZiX Terminal" -e /System/Compatibility/bin/bash "$@"
EOF
chmod 0755 "${AUZIX_ROOT}/System/Tools/launch-auzix-terminal"

cat > "${AUZIX_ROOT}/System/PackageDB/Terminology-${TERM_VERSION}.auzix.json" <<EOF
{
  "name": "Terminology",
  "version": "${TERM_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/Terminology/${TERM_VERSION}",
  "commands": [
    "/Programs/Terminology/${TERM_VERSION}/Commands/terminology"
  ],
  "compatibility_exports": [
    "/Programs/Terminology/current",
    "/System/Compatibility/bin/terminology",
    "/System/Compatibility/usr/bin/terminology",
    "/System/Compatibility/usr/share/applications/terminology.desktop",
    "/System/Compatibility/usr/share/applications/auzix-terminal.desktop",
    "/System/Tools/launch-auzix-terminal"
  ],
  "notes": "Host-packaged Terminology terminal for graphical bring-up validation. Menu launch flows through /System/Tools/launch-auzix-terminal so AUZiX PATH, library, XDG, cert, and software-rendering environment is inherited before Terminology starts."
}
EOF

log "Terminology installed at ${TERM_PROGRAM}"
