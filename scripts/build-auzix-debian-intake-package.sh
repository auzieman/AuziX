#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
DEBIAN_PACKAGE="${2:-}"
WORK_DIR="${ROOT_DIR}/out/auzix-packages/trixie/${DEBIAN_PACKAGE}"

log() {
  printf '[auzix-trixie-package] %s\n' "$*" >&2
}

auzix_native_name() {
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
      net|tools)
        native+="${part^}"
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
      *)
        native+="${part^}"
        ;;
    esac
  done
  printf '%s\n' "${native}"
}

debian_depends_to_native_json() {
  local depends_text="$1"
  local dep clean native
  {
    tr ',' '\n' <<<"${depends_text}" |
      while IFS= read -r dep; do
        clean="${dep%%|*}"
        clean="$(sed -E 's/[[:space:]]*\\([^)]*\\)//g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/:[A-Za-z0-9_-]+$//' <<<"${clean}")"
        [[ "${clean}" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || continue
        native="$(auzix_native_name "${clean}")"
        [[ -n "${native}" ]] || continue
        printf '%s\n' "${native}"
      done | awk '!seen[$0]++'
  } | jq -R -s 'split("\n") | map(select(length > 0))'
}

[[ "${DEBIAN_PACKAGE}" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || {
  log "invalid Debian package name: ${DEBIAN_PACKAGE}"
  exit 1
}
[[ -d "${AUZIX_ROOT}/System/PackageDB" ]] || {
  log "AuziX root is missing: ${AUZIX_ROOT}"
  exit 1
}
for command_name in apt-get dpkg-deb jq rsync; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    log "missing command: ${command_name}"
    exit 1
  }
done

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}/debs" "${WORK_DIR}/extract"
(
  cd "${WORK_DIR}/debs"
  apt-get download "${DEBIAN_PACKAGE}" >/dev/null
)

deb_path="$(find "${WORK_DIR}/debs" -maxdepth 1 -type f -name '*.deb' -print -quit)"
[[ -n "${deb_path}" ]] || {
  log "no Debian archive downloaded for ${DEBIAN_PACKAGE}"
  exit 1
}

package_name="$(dpkg-deb -f "${deb_path}" Package)"
package_version="$(dpkg-deb -f "${deb_path}" Version)"
package_arch="$(dpkg-deb -f "${deb_path}" Architecture)"
package_description="$(dpkg-deb -f "${deb_path}" Description | sed -n '1p')"
package_depends="$(dpkg-deb -f "${deb_path}" Depends 2>/dev/null || true)"
native_depends_json="$(debian_depends_to_native_json "${package_depends}")"
safe_version="$(tr '/: ' '---' <<<"${package_version}" | tr -cd 'A-Za-z0-9_.+~-')"
native_name="$(auzix_native_name "${package_name}")"
program_root="${AUZIX_ROOT}/Programs/${native_name}/${safe_version}"
receipt_path="${AUZIX_ROOT}/System/PackageDB/${native_name}-${safe_version}.auzix.json"
legacy_program_root="${AUZIX_ROOT}/Programs/DebianPackages/${package_name}/${safe_version}"
legacy_receipt_path="${AUZIX_ROOT}/System/PackageDB/Debian.${package_name}-${safe_version}.auzix.json"

dpkg-deb -x "${deb_path}" "${WORK_DIR}/extract"
rm -rf "${program_root}" "${legacy_program_root}"
rm -f "${receipt_path}" "${legacy_receipt_path}"
mkdir -p "${program_root}/RootFS" "${program_root}/Metadata"
rsync -a "${WORK_DIR}/extract/" "${program_root}/RootFS/"
dpkg-deb -f "${deb_path}" >"${program_root}/Metadata/debian-control.txt"
ln -sfn "/Programs/${native_name}/${safe_version}" \
  "${AUZIX_ROOT}/Programs/${native_name}/current"
payload_file_count="$(find "${program_root}/RootFS" -type f | wc -l | tr -d ' ')"
payload_size_bytes="$(du -sb "${program_root}/RootFS" | awk '{print $1}')"
repack_class="payload"
if [[ "${payload_file_count}" -lt 25 && -n "${package_depends}" ]]; then
  repack_class="dependency-bundle"
fi

jq -n \
  --arg name "${native_name}" \
  --arg version "${safe_version}" \
  --arg source_package "${package_name}" \
  --arg source_version "${package_version}" \
  --arg source_architecture "${package_arch}" \
  --arg source_suite "trixie" \
  --arg upstream_depends "${package_depends}" \
  --arg description "${package_description}" \
  --arg prefix "/Programs/${native_name}/${safe_version}" \
  --arg current "/Programs/${native_name}/current" \
  --arg repack_class "${repack_class}" \
  --argjson depends "${native_depends_json}" \
  --argjson payload_file_count "${payload_file_count}" \
  --argjson payload_size_bytes "${payload_size_bytes}" \
  '{
    name: $name,
    version: $version,
    kind: "program",
    migration_stage: "stage-1-auzix-native-repack",
    prefix: $prefix,
    paths: {prefix: $prefix, current: $current},
    depends: $depends,
    description: $description,
    source: {
      type: "debian-binary-package",
      distribution: "debian",
      suite: $source_suite,
      package: $source_package,
      version: $source_version,
      architecture: $source_architecture,
      upstream_depends: $upstream_depends,
      upstream_depends_native: $depends,
      payload_file_count: $payload_file_count,
      payload_size_bytes: $payload_size_bytes,
      repack_class: $repack_class
    },
    notes: "Experimental Trixie intake package. The source is Debian, but the package identity and install prefix are AUZiX-native."
  }' >"${receipt_path}"

log "built ${native_name} ${package_version} from ${package_name} (${repack_class}, ${payload_file_count} files)"
