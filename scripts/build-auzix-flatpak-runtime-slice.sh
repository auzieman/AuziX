#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/extended-ports/AuZiXRoot}"
REPORT_DIR="${ROOT_DIR}/out/source-workbench/extended-ports"

mkdir -p "${AUZIX_ROOT}/System/PackageDB" "${AUZIX_ROOT}/Programs" "${REPORT_DIR}"

native_receipt_exists() {
  local native_name="$1"
  find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
    -name "${native_name}-*.auzix.json" -print -quit 2>/dev/null | grep -q .
}

ensure_debian_intake_package() {
  local debian_package="$1"
  local native_name
  native_name="$("${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" \
    --print-native-name "${debian_package}")"
  if native_receipt_exists "${native_name}"; then
    printf '[flatpak-runtime] reuse %s from existing Debian intake\n' "${native_name}" >&2
    return 0
  fi
  printf '[flatpak-runtime] intake missing %s via Debian package %s\n' \
    "${native_name}" "${debian_package}" >&2
  "${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" \
    "${AUZIX_ROOT}" "${debian_package}"
}

# Do not bulldoze the big Debian intake output here.  The workstation rebase
# already resolved and staged Flatpak's real Debian runtime dependencies.  This
# layer only fills missing command packages and adds AUZiX state/settings hints.
ensure_debian_intake_package bubblewrap
ensure_debian_intake_package ostree
ensure_debian_intake_package xdg-dbus-proxy
ensure_debian_intake_package gnupg
ensure_debian_intake_package gpg
ensure_debian_intake_package gpgconf
ensure_debian_intake_package gpg-agent
ensure_debian_intake_package gpgsm
ensure_debian_intake_package gpgv
ensure_debian_intake_package flatpak

mkdir -p \
  "${AUZIX_ROOT}/System/State/flatpak" \
  "${AUZIX_ROOT}/System/State/ostree/repo" \
  "${AUZIX_ROOT}/System/State/gnupg" \
  "${AUZIX_ROOT}/System/Settings/flatpak"

flatpak_receipt="$(find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name 'Flatpak-*.auzix.json' | sort | tail -1)"
ostree_receipt="$(find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name 'Ostree-*.auzix.json' | sort | tail -1)"

jq '.paths.state = "/System/State/flatpak" | .paths.settings = "/System/Settings/flatpak"' \
  "${flatpak_receipt}" >"${flatpak_receipt}.tmp"
mv "${flatpak_receipt}.tmp" "${flatpak_receipt}"

if [[ -n "${ostree_receipt}" ]]; then
  jq '.paths.state = "/System/State/ostree"' \
    "${ostree_receipt}" >"${ostree_receipt}.tmp"
  mv "${ostree_receipt}.tmp" "${ostree_receipt}"
fi

mapfile -t receipts < <(find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
  \( -name 'Bubblewrap-*.auzix.json' -o -name 'Ostree-*.auzix.json' \
     -o -name 'XdgDBusProxy-*.auzix.json' -o -name 'Gnupg-*.auzix.json' \
     -o -name 'Gpg-*.auzix.json' -o -name 'Gpgconf-*.auzix.json' \
     -o -name 'GpgAgent-*.auzix.json' -o -name 'Gpgsm-*.auzix.json' \
     -o -name 'Gpgv-*.auzix.json' -o -name 'Flatpak-*.auzix.json' \) | sort)

jq -s '{format:"auzix-flatpak-runtime-slice-v1", status:"passed", packages:.}' \
  "${receipts[@]}" >"${REPORT_DIR}/flatpak-runtime.report.json"

printf '[flatpak-runtime] staged Debian-intake Flatpak runtime packages (%s receipts)\n' "${#receipts[@]}"
