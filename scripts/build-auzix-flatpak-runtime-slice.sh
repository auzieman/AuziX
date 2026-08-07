#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/extended-ports/AuZiXRoot}"
REPORT_DIR="${ROOT_DIR}/out/source-workbench/extended-ports"

mkdir -p "${AUZIX_ROOT}/System/PackageDB" "${AUZIX_ROOT}/Programs" "${REPORT_DIR}"

build_package() {
  local name="$1"
  local recipe="$2"
  rm -rf "${AUZIX_ROOT}/Programs/${name}"
  find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
    -name "${name}-*.auzix.json" -delete 2>/dev/null || true
  "${ROOT_DIR}/scripts/build-auzix-command-suite-package.sh" \
    "${AUZIX_ROOT}" "${ROOT_DIR}/packages/${recipe}"
}

build_package Bubblewrap bubblewrap.command-suite.json
build_package OSTree ostree.command-suite.json
build_package XdgDbusProxy xdg-dbus-proxy.command-suite.json
build_package GnuPG gnupg.command-suite.json
build_package Flatpak flatpak.command-suite.json

mkdir -p \
  "${AUZIX_ROOT}/System/State/flatpak" \
  "${AUZIX_ROOT}/System/State/ostree/repo" \
  "${AUZIX_ROOT}/System/State/gnupg" \
  "${AUZIX_ROOT}/System/Settings/flatpak"

flatpak_receipt="$(find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name 'Flatpak-*.auzix.json' | sort | tail -1)"
ostree_receipt="$(find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name 'OSTree-*.auzix.json' | sort | tail -1)"

jq '.paths.state = "/System/State/flatpak" | .paths.settings = "/System/Settings/flatpak"' \
  "${flatpak_receipt}" >"${flatpak_receipt}.tmp"
mv "${flatpak_receipt}.tmp" "${flatpak_receipt}"

jq '.paths.state = "/System/State/ostree"' \
  "${ostree_receipt}" >"${ostree_receipt}.tmp"
mv "${ostree_receipt}.tmp" "${ostree_receipt}"

mapfile -t receipts < <(find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
  \( -name 'Bubblewrap-*.auzix.json' -o -name 'OSTree-*.auzix.json' \
     -o -name 'XdgDbusProxy-*.auzix.json' -o -name 'GnuPG-*.auzix.json' \
     -o -name 'Flatpak-*.auzix.json' \) | sort)
[[ "${#receipts[@]}" -eq 5 ]]

jq -s '{format:"auzix-flatpak-runtime-slice-v1", status:"passed", packages:.}' \
  "${receipts[@]}" >"${REPORT_DIR}/flatpak-runtime.report.json"

printf '[flatpak-runtime] built Bubblewrap, OSTree, XdgDbusProxy, GnuPG, and Flatpak\n'
