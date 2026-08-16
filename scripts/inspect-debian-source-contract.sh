#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="${1:?usage: inspect-debian-source-contract.sh <debian-source-package> [out-dir]}"
OUT_DIR="${2:-${ROOT_DIR}/out/debian-source-guidebook/${PACKAGE}}"
SRC_PARENT="${OUT_DIR}/source"
REPORT_DIR="${OUT_DIR}/report"

mkdir -p "${SRC_PARENT}" "${REPORT_DIR}"

log() {
  printf '[debian-source-guidebook] %s\n' "$*" >&2
}

write_section() {
  local title="$1"
  local file="$2"
  {
    printf '\n## %s\n\n' "${title}"
    if [[ -s "${file}" ]]; then
      sed -n '1,240p' "${file}"
    else
      printf '(empty)\n'
    fi
  } >>"${REPORT_DIR}/guidebook.md"
}

fetch_source() {
  if find "${SRC_PARENT}" -mindepth 1 -maxdepth 1 -type d -name "${PACKAGE}-*" -print -quit | grep -q .; then
    return
  fi
  (
    cd "${SRC_PARENT}"
    apt-get source "${PACKAGE}"
  )
}

source_dir() {
  local matched
  matched="$(find "${SRC_PARENT}" -mindepth 1 -maxdepth 1 -type d -name "${PACKAGE}-*" -print | sort | tail -n 1)"
  if [[ -n "${matched}" ]]; then
    printf '%s\n' "${matched}"
    return
  fi
  # apt-get source can legally choose a differently named source package for a
  # binary package, e.g. binary "enlightenment" comes from source "e17".
  find "${SRC_PARENT}" -mindepth 1 -maxdepth 1 -type d -print | sort | tail -n 1
}

fetch_source
SRC_DIR="$(source_dir)"
[[ -n "${SRC_DIR}" ]] || {
  log "source directory not found for ${PACKAGE}"
  exit 1
}

: >"${REPORT_DIR}/guidebook.md"
{
  printf '# Debian source guidebook: %s\n\n' "${PACKAGE}"
  printf -- '- source_dir: `%s`\n' "${SRC_DIR}"
  printf -- '- generated_at: `%s`\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >>"${REPORT_DIR}/guidebook.md"

if [[ -f "${SRC_DIR}/debian/control" ]]; then
  awk '
    BEGIN { section = "" }
    /^Source:/ { section = "source" }
    /^Package:/ { section = "binary" }
    /^(Source|Package|Build-Depends|Build-Depends-Indep|Architecture|Depends|Recommends|Suggests|Description):/ {
      print
      next
    }
    /^[[:space:]]/ && section != "" { print }
  ' "${SRC_DIR}/debian/control" >"${REPORT_DIR}/control-summary.txt"
else
  : >"${REPORT_DIR}/control-summary.txt"
fi

{
  find "${SRC_DIR}/debian" -maxdepth 2 -type f \
    \( -name 'rules' \
      -o -name '*.mk' \
      -o -name '*.install' \
      -o -name '*.links' \
      -o -name '*.dirs' \
      -o -name '*.postinst' \
      -o -name '*.preinst' \
      -o -name '*.postrm' \
      -o -name '*.prerm' \
      -o -name '*.triggers' \
      -o -name '*.maintscript' \
      -o -name '*.service' \
      -o -name '*.desktop' \
      -o -name '*.apparmor' \
      -o -name '*.policy' \
      -o -path '*/tests/control' \
      -o -path '*/scripts/*' \) \
    -printf '%P\n' 2>/dev/null | sort
} >"${REPORT_DIR}/interesting-files.txt"

{
  grep -RInE \
    'configure|autogen|CONFIGURE|DEB_CONFIGURE|dh_auto_configure|dh_auto_build|dh_auto_install|make |ninja|meson|cmake|move_wrappers|create_package_directory|dh_install|mv |ln -s|update-alternatives|glib-compile-schemas|gtk-update-icon-cache|update-desktop-database|dbus|polkit|apparmor|systemd|oosplash|soffice|convert-to|autopkgtest|Tests:|Test-Command:' \
    "${SRC_DIR}/debian" 2>/dev/null || true
} >"${REPORT_DIR}/recipe-signals.txt"

write_section "Control summary" "${REPORT_DIR}/control-summary.txt"
write_section "Interesting Debian recipe files" "${REPORT_DIR}/interesting-files.txt"
write_section "Recipe signals" "${REPORT_DIR}/recipe-signals.txt"

if [[ -f "${SRC_DIR}/debian/tests/control" ]]; then
  write_section "Autopkgtest control" "${SRC_DIR}/debian/tests/control"
fi

if [[ -f "${SRC_DIR}/debian/rules" ]]; then
  {
    printf '\n## debian/rules configure/build excerpts\n\n'
    grep -nE 'configure|autogen|CONFIGURE|dh_auto_configure|dh_auto_build|dh_auto_install|override_dh_auto' \
      "${SRC_DIR}/debian/rules" || true
  } >>"${REPORT_DIR}/guidebook.md"
fi

if [[ -f "${SRC_DIR}/debian/scripts/gid2pkgdirs.sh" ]]; then
  {
    printf '\n## LibreOffice package split excerpt\n\n'
    sed -n '110,165p' "${SRC_DIR}/debian/scripts/gid2pkgdirs.sh"
  } >>"${REPORT_DIR}/guidebook.md"
fi

log "guidebook report: ${REPORT_DIR}/guidebook.md"
