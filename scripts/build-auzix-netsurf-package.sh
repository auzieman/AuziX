#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
WORK_DIR="${ROOT_DIR}/out/auzix-packages/netsurf"
APT_PACKAGES=(netsurf-gtk netsurf-common)
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"
RUNTIME_USR="${AUZIX_ROOT}/System/Compatibility/usr"

log() {
  printf '[auzix-netsurf] %s\n' "$*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

detect_version() {
  local version
  version="$(apt-cache show netsurf-gtk 2>/dev/null | awk '/^Version:/ {print $2; exit}')"
  if [[ -z "${version}" ]]; then
    printf 'host\n'
  else
    printf '%s\n' "${version}"
  fi
}

copy_dep_path() {
  local dep="$1"
  [[ -e "${dep}" ]] || return 0
  case "${dep}" in
    /lib64/*)
      install -D -m 0755 "${dep}" "${RUNTIME_LIB64}/$(basename "${dep}")"
      install -D -m 0755 "${dep}" "${NETSURF_PROGRAM}/Libraries/$(basename "${dep}")"
      ;;
    /lib/x86_64-linux-gnu/*|/usr/lib/x86_64-linux-gnu/*)
      install -D -m 0755 "${dep}" "${RUNTIME_LIB}/$(basename "${dep}")"
      install -D -m 0755 "${dep}" "${NETSURF_PROGRAM}/Libraries/$(basename "${dep}")"
      ;;
    /usr/lib/*)
      install -D -m 0755 "${dep}" "${RUNTIME_USR}/lib/${dep#/usr/lib/}"
      install -D -m 0755 "${dep}" "${NETSURF_PROGRAM}/Libraries/${dep#/usr/lib/}"
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

require_cmd apt-get
require_cmd apt-cache
require_cmd dpkg-deb
require_cmd file
require_cmd install
require_cmd ldd

NETSURF_VERSION="${AUZIX_NETSURF_VERSION:-$(detect_version)}"
NETSURF_PROGRAM="${AUZIX_ROOT}/Programs/NetSurf/${NETSURF_VERSION}"

rm -rf "${WORK_DIR}"
rm -rf "${NETSURF_PROGRAM}"
mkdir -p "${WORK_DIR}/debs" "${WORK_DIR}/extract"

(
  cd "${WORK_DIR}/debs"
  apt-get download "${APT_PACKAGES[@]}" >/dev/null
)

for deb in "${WORK_DIR}"/debs/*.deb; do
  dpkg-deb -x "${deb}" "${WORK_DIR}/extract"
done

if [[ ! -x "${WORK_DIR}/extract/usr/bin/netsurf-gtk" ]]; then
  printf 'NetSurf binary not found in downloaded packages.\n' >&2
  exit 1
fi

mkdir -p \
  "${NETSURF_PROGRAM}/Commands" \
  "${NETSURF_PROGRAM}/Libraries" \
  "${NETSURF_PROGRAM}/Resources/share" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${RUNTIME_USR}/bin" \
  "${RUNTIME_USR}/share/applications" \
  "${RUNTIME_USR}/share/pixmaps" \
  "${RUNTIME_USR}/share/netsurf" \
  "${RUNTIME_USR}/share/fonts/truetype" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}" \
  "${AUZIX_ROOT}/System/PackageDB"

install -D -m 0755 "${WORK_DIR}/extract/usr/bin/netsurf-gtk" \
  "${NETSURF_PROGRAM}/Commands/netsurf-gtk.real"
copy_runtime_deps "${WORK_DIR}/extract/usr/bin/netsurf-gtk"

cat > "${NETSURF_PROGRAM}/Commands/netsurf" <<'EOF'
#!/System/Compatibility/bin/sh
set -eu

export NETSURFRES="${NETSURFRES:-/System/Compatibility/usr/share/netsurf}"
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/System/Compatibility/usr/share:/usr/share}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME:-/Users/auzix}/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME:-/Users/auzix}/.cache}"
export SSL_CERT_DIR="${SSL_CERT_DIR:-/System/Compatibility/etc/ssl/certs}"
export GDK_BACKEND="${GDK_BACKEND:-x11}"
export LD_LIBRARY_PATH="/Programs/NetSurf/current/Libraries:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

exec /Programs/NetSurf/current/Commands/netsurf-gtk.real "$@"
EOF
chmod 0755 "${NETSURF_PROGRAM}/Commands/netsurf"

ln -sfn "/Programs/NetSurf/${NETSURF_VERSION}" "${AUZIX_ROOT}/Programs/NetSurf/current"
ln -sfn /Programs/NetSurf/current/Commands/netsurf "${AUZIX_ROOT}/System/Compatibility/bin/netsurf"
ln -sfn /Programs/NetSurf/current/Commands/netsurf "${AUZIX_ROOT}/System/Compatibility/bin/netsurf-gtk"
ln -sfn /Programs/NetSurf/current/Commands/netsurf "${RUNTIME_USR}/bin/netsurf"
ln -sfn /Programs/NetSurf/current/Commands/netsurf "${RUNTIME_USR}/bin/netsurf-gtk"

copy_dir_if_present "${WORK_DIR}/extract/usr/share/netsurf" "${NETSURF_PROGRAM}/Resources/share/netsurf"
rm -rf "${RUNTIME_USR}/share/netsurf"
cp -a "${NETSURF_PROGRAM}/Resources/share/netsurf" "${RUNTIME_USR}/share/netsurf"

if [[ -f "${WORK_DIR}/extract/usr/share/applications/netsurf-gtk.desktop" ]]; then
  install -D -m 0644 "${WORK_DIR}/extract/usr/share/applications/netsurf-gtk.desktop" \
    "${RUNTIME_USR}/share/applications/netsurf-gtk.desktop"
fi
cat > "${RUNTIME_USR}/share/applications/auzix-netsurf.desktop" <<'EOF_DESKTOP'
[Desktop Entry]
Type=Application
Name=NetSurf
Comment=Browse the web with a small GTK browser
TryExec=netsurf
Exec=netsurf %u
Icon=netsurf
Categories=Network;WebBrowser;
Terminal=false
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
EOF_DESKTOP

if compgen -G "${WORK_DIR}/extract/usr/share/pixmaps/netsurf*" >/dev/null; then
  cp -a "${WORK_DIR}/extract/usr/share/pixmaps"/netsurf* "${RUNTIME_USR}/share/pixmaps/" 2>/dev/null || true
fi
copy_dir_if_present /etc/ssl/certs "${AUZIX_ROOT}/System/Compatibility/etc/ssl/certs"
copy_dir_if_present /usr/share/ca-certificates "${RUNTIME_USR}/share/ca-certificates"
copy_dir_if_present /usr/share/fonts/truetype/dejavu "${RUNTIME_USR}/share/fonts/truetype/dejavu"

find "${NETSURF_PROGRAM}" "${RUNTIME_USR}/share/netsurf" -type f 2>/dev/null |
while IFS= read -r file_path; do
  if file "${file_path}" | grep -q 'ELF'; then
    copy_runtime_deps "${file_path}" || true
  fi
done

cat > "${AUZIX_ROOT}/System/PackageDB/NetSurf-${NETSURF_VERSION}.auzix.json" <<EOF
{
  "name": "NetSurf",
  "version": "${NETSURF_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/NetSurf/${NETSURF_VERSION}",
  "paths": {
    "current": "/Programs/NetSurf/current"
  },
  "commands": [
    "/Programs/NetSurf/${NETSURF_VERSION}/Commands/netsurf",
    "/Programs/NetSurf/${NETSURF_VERSION}/Commands/netsurf-gtk.real"
  ],
  "runtime_libraries": [
    "/Programs/NetSurf/${NETSURF_VERSION}/Libraries"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/netsurf",
    "/System/Compatibility/bin/netsurf-gtk",
    "/System/Compatibility/usr/bin/netsurf",
    "/System/Compatibility/usr/bin/netsurf-gtk",
    "/System/Compatibility/usr/share/applications/auzix-netsurf.desktop",
    "/System/Compatibility/usr/share/applications/netsurf-gtk.desktop"
  ],
  "notes": "Small GTK browser proof package. Built from Debian packages via apt-get download; Trixie currently offers NetSurf 3.11 while the Bookworm build host offers 3.10."
}
EOF

log "NetSurf installed at ${NETSURF_PROGRAM}"
