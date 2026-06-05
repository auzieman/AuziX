#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"

detect_host_xterm_version() {
  local version
  version="$(dpkg-query -W -f='${Version}' xterm 2>/dev/null || true)"
  if [[ -n "${version}" ]]; then
    printf '%s\n' "${version}"
    return 0
  fi
  printf 'host\n'
}

XTERM_VERSION="${AUZIX_XTERM_VERSION:-$(detect_host_xterm_version)}"
XTERM_PROGRAM="${AUZIX_ROOT}/Programs/XTerm/${XTERM_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"
RUNTIME_USR="${AUZIX_ROOT}/System/Compatibility/usr"

log() {
  printf '[auzix-xterm] %s\n' "$*" >&2
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

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

require_cmd xterm
require_cmd file
require_cmd install
require_cmd ldd

mkdir -p \
  "${XTERM_PROGRAM}/Commands" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${RUNTIME_USR}/bin" \
  "${RUNTIME_USR}/share/applications" \
  "${RUNTIME_USR}/share/pixmaps" \
  "${RUNTIME_USR}/share/X11/app-defaults" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}" \
  "${AUZIX_ROOT}/System/PackageDB"

copy_binary "$(command -v xterm)" "${XTERM_PROGRAM}/Commands/xterm"
ln -sfn "/Programs/XTerm/${XTERM_VERSION}/Commands/xterm" "${AUZIX_ROOT}/System/Compatibility/bin/xterm"
ln -sfn "/Programs/XTerm/${XTERM_VERSION}/Commands/xterm" "${RUNTIME_USR}/bin/xterm"

if command -v uxterm >/dev/null 2>&1; then
  copy_binary "$(command -v uxterm)" "${XTERM_PROGRAM}/Commands/uxterm"
  ln -sfn "/Programs/XTerm/${XTERM_VERSION}/Commands/uxterm" "${AUZIX_ROOT}/System/Compatibility/bin/uxterm"
  ln -sfn "/Programs/XTerm/${XTERM_VERSION}/Commands/uxterm" "${RUNTIME_USR}/bin/uxterm"
fi

for app_defaults in /etc/X11/app-defaults/XTerm /etc/X11/app-defaults/XTerm-color /usr/share/X11/app-defaults/XTerm /usr/share/X11/app-defaults/XTerm-color; do
  [[ -f "${app_defaults}" ]] || continue
  install -D -m 0644 "${app_defaults}" "${RUNTIME_USR}/share/X11/app-defaults/$(basename "${app_defaults}")"
done

if [[ -f /usr/share/pixmaps/xterm-color_48x48.xpm ]]; then
  install -D -m 0644 /usr/share/pixmaps/xterm-color_48x48.xpm "${RUNTIME_USR}/share/pixmaps/xterm-color_48x48.xpm"
fi

cat > "${RUNTIME_USR}/share/applications/auzix-xterm.desktop" <<'EOF_DESKTOP'
[Desktop Entry]
Type=Application
Name=Auzix XTerm
Comment=Open a local Auzix shell
TryExec=xterm
Exec=xterm -fa Monospace -fs 11 -bg black -fg white -e /System/Compatibility/bin/bash
Icon=xterm-color_48x48
Categories=System;TerminalEmulator;
Terminal=false
EOF_DESKTOP

cat > "${AUZIX_ROOT}/System/PackageDB/XTerm-${XTERM_VERSION}.auzix.json" <<EOF
{
  "name": "XTerm",
  "version": "${XTERM_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/XTerm/${XTERM_VERSION}",
  "commands": [
    "/Programs/XTerm/${XTERM_VERSION}/Commands/xterm"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/xterm",
    "/System/Compatibility/usr/bin/xterm",
    "/System/Compatibility/usr/share/applications/auzix-xterm.desktop"
  ],
  "notes": "Host-packaged XTerm fallback terminal for X11 graphical bring-up when EFL terminals are unstable."
}
EOF

log "XTerm installed at ${XTERM_PROGRAM}"
