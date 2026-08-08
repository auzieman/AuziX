#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUIDEBOOK_DIR="${1:-${ROOT_DIR}/out/vmid132-guidebook}"
MANIFEST="${2:-${ROOT_DIR}/profiles/packages/auzix-vmid132-workstation.packages}"
AUZIX_ROOT="${3:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
REPORT="${ROOT_DIR}/out/package-bot/guidebook-manifest-validation.tsv"

mkdir -p "$(dirname "${REPORT}")"

manual_list="${GUIDEBOOK_DIR}/apt-manual-packages.txt"
installed_table="${GUIDEBOOK_DIR}/dpkg-installed.tsv"

[[ -s "${manual_list}" ]] || {
  printf 'guidebook manifest validation: missing manual list: %s\n' "${manual_list}" >&2
  exit 2
}
[[ -s "${installed_table}" ]] || {
  printf 'guidebook manifest validation: missing installed table: %s\n' "${installed_table}" >&2
  exit 2
}
[[ -s "${MANIFEST}" ]] || {
  printf 'guidebook manifest validation: missing AUZiX manifest: %s\n' "${MANIFEST}" >&2
  exit 2
}

native_name() {
  local raw="$1"
  local part native=""
  IFS='-+.' read -ra parts <<<"${raw}"
  for part in "${parts[@]}"; do
    [[ -n "${part}" ]] || continue
    case "${part}" in
      api|dbus|dns|gcc|gimp|gtk|html|http|ip|pdf|pip|ssh|ssl|ui|vim|vlc|x11|xcb|xfce|xml)
        native+="${part^^}"
        ;;
      cmake)
        native+="CMake"
        ;;
      gnumeric)
        native+="Gnumeric"
        ;;
      imagemagick)
        native+="ImageMagick"
        ;;
      libreoffice)
        native+="LibreOffice"
        ;;
      librewolf)
        native+="LibreWolf"
        ;;
      lightdm)
        native+="LightDM"
        ;;
      pcmanfm)
        native+="PCManFM"
        ;;
      xorg)
        native+="Xorg"
        ;;
      zathura)
        native+="Zathura"
        ;;
      abiword)
        native+="AbiWord"
        ;;
      *)
        native+="${part^}"
        ;;
    esac
  done
  printf '%s\n' "${native}"
}

printf 'package\tnative_name\tstage\tstatus\tnotes\n' >"${REPORT}"

failures=0
while IFS= read -r package_name; do
  [[ -n "${package_name}" && ! "${package_name}" =~ ^# ]] || continue

  native="$(native_name "${package_name}")"
  notes=()
  status="pass"
  stage="guidebook"

  if ! grep -Fxq "${package_name}" "${manual_list}"; then
    status="fail"
    stage="manifest"
    notes+=("not-in-vmid132-manual-list")
  fi

  if ! awk -F '\t' -v pkg="${package_name}" '
    {
      binary = $1
      sub(/:[A-Za-z0-9_-]+$/, "", binary)
      if (binary == pkg) found=1
    }
    END {exit found ? 0 : 1}
  ' "${installed_table}"; then
    status="fail"
    stage="metadata"
    notes+=("not-in-vmid132-dpkg-installed-table")
  fi

  if [[ -d "${AUZIX_ROOT}/System/PackageDB" ]]; then
    if ! find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
      \( -name "${native}-*.auzix.json" -o -name "Debian.${package_name}-*.auzix.json" \) |
      grep -q .; then
      if [[ "${status}" == "pass" ]]; then
        status="warn"
        stage="auzix-package"
      fi
      notes+=("no-auzix-receipt-yet")
    fi
  else
    if [[ "${status}" == "pass" ]]; then
      status="warn"
      stage="auzix-root"
    fi
    notes+=("auzix-root-not-present")
  fi

  note_text="$(IFS=,; printf '%s' "${notes[*]:-}")"
  printf '%s\t%s\t%s\t%s\t%s\n' "${package_name}" "${native}" "${stage}" "${status}" "${note_text}" >>"${REPORT}"
  [[ "${status}" != "fail" ]] || failures=$((failures + 1))
done < <(awk 'NF && $1 !~ /^#/ {print $1}' "${MANIFEST}" | sort -u)

warns="$(awk -F '\t' 'NR > 1 && $4 == "warn" {count++} END {print count+0}' "${REPORT}")"
printf 'guidebook manifest validation: failures=%s warnings=%s report=%s\n' "${failures}" "${warns}" "${REPORT}" >&2

if (( failures > 0 )); then
  exit 1
fi
