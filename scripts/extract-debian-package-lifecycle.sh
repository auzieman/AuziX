#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="${1:?usage: extract-debian-package-lifecycle.sh <debian-binary-package> [out-dir]}"
OUT_DIR="${2:-${ROOT_DIR}/out/debian-package-lifecycle/${PACKAGE}}"
DEB_DIR="${OUT_DIR}/debs"
EXTRACT_DIR="${OUT_DIR}/extract"
REPORT_DIR="${OUT_DIR}/report"

mkdir -p "${DEB_DIR}" "${EXTRACT_DIR}" "${REPORT_DIR}"

log() {
  printf '[debian-package-lifecycle] %s\n' "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  }
}

require_cmd apt-get
require_cmd dpkg-deb
require_cmd awk
require_cmd find

download_deb() {
  if find "${DEB_DIR}" -maxdepth 1 -type f -name "${PACKAGE}_*.deb" -print -quit | grep -q .; then
    return
  fi
  (
    cd "${DEB_DIR}"
    apt-get download "${PACKAGE}"
  )
}

deb_path() {
  find "${DEB_DIR}" -maxdepth 1 -type f -name "${PACKAGE}_*.deb" -print | sort | tail -n 1
}

extract_deb() {
  local deb="$1"
  rm -rf "${EXTRACT_DIR}/control" "${EXTRACT_DIR}/rootfs"
  mkdir -p "${EXTRACT_DIR}/control" "${EXTRACT_DIR}/rootfs"
  dpkg-deb -e "${deb}" "${EXTRACT_DIR}/control"
  dpkg-deb -x "${deb}" "${EXTRACT_DIR}/rootfs"
}

capture_file_list() {
  (
    cd "${EXTRACT_DIR}/rootfs"
    find . -mindepth 1 -printf '%P\n' | sort
  ) >"${REPORT_DIR}/files.txt"
}

capture_surfaces() {
  local root="${EXTRACT_DIR}/rootfs"
  {
    find "${root}" -type f \
      \( -path '*/usr/bin/*' \
        -o -path '*/usr/sbin/*' \
        -o -path '*/bin/*' \
        -o -path '*/sbin/*' \) \
      -printf '%P\n' 2>/dev/null | sort
  } >"${REPORT_DIR}/commands.txt"

  {
    find "${root}" -type f \
      \( -path '*/usr/share/applications/*.desktop' \
        -o -path '*/usr/share/dbus-1/*/*.service' \
        -o -path '*/usr/share/polkit-1/**/*.policy' \
        -o -path '*/lib/systemd/system/*' \
        -o -path '*/usr/lib/systemd/system/*' \
        -o -path '*/usr/share/glib-2.0/schemas/*' \
        -o -path '*/usr/share/icons/*' \
        -o -path '*/usr/share/mime/*' \
        -o -path '*/usr/share/metainfo/*' \) \
      -printf '%P\n' 2>/dev/null | sort
  } >"${REPORT_DIR}/desktop-service-data.txt"

  {
    grep -RInE \
      '(^|[^A-Za-z0-9_])(/usr|/etc|/var|/bin|/sbin|/lib|/run|/tmp|/root)(/| |"|'\''|$)|setuid|setgid|chmod|chown|adduser|useradd|groupadd|update-|glib-compile-schemas|gtk-update-icon-cache|update-desktop-database|dbus|systemctl|systemd|tmpfiles|polkit|capabilities|setcap|ldconfig|install-info|mime' \
      "${EXTRACT_DIR}/control" "${root}" 2>/dev/null || true
  } >"${REPORT_DIR}/lifecycle-signals.txt"
}

write_report() {
  local deb="$1"
  local control="${EXTRACT_DIR}/control/control"
  {
    printf '# Debian package lifecycle: %s\n\n' "${PACKAGE}"
    printf -- '- deb: `%s`\n' "${deb}"
    printf -- '- generated_at: `%s`\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    printf '## Control\n\n'
    if [[ -s "${control}" ]]; then
      sed -n '1,220p' "${control}"
    else
      printf '(missing)\n'
    fi

    printf '\n## Maintainer scripts\n\n'
    find "${EXTRACT_DIR}/control" -maxdepth 1 -type f \
      \( -name preinst -o -name postinst -o -name prerm -o -name postrm -o -name triggers -o -name conffiles -o -name shlibs -o -name symbols \) \
      -printf '%f\n' | sort | while read -r f; do
        printf '\n### %s\n\n' "$f"
        sed -n '1,260p' "${EXTRACT_DIR}/control/$f"
      done

    printf '\n## Commands\n\n'
    sed -n '1,220p' "${REPORT_DIR}/commands.txt"

    printf '\n## Desktop/service/data surfaces\n\n'
    sed -n '1,260p' "${REPORT_DIR}/desktop-service-data.txt"

    printf '\n## Lifecycle/path signals\n\n'
    sed -n '1,320p' "${REPORT_DIR}/lifecycle-signals.txt"
  } >"${REPORT_DIR}/lifecycle.md"
}

download_deb
DEB="$(deb_path)"
[[ -n "${DEB}" ]] || {
  log "no .deb found for ${PACKAGE}"
  exit 1
}
extract_deb "${DEB}"
capture_file_list
capture_surfaces
write_report "${DEB}"
log "report: ${REPORT_DIR}/lifecycle.md"

