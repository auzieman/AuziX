#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
DEBIAN_PACKAGE="${2:-}"
WORK_DIR="${ROOT_DIR}/out/auzix-packages/trixie/${DEBIAN_PACKAGE}"

log() {
  printf '[auzix-trixie-package] %s\n' "$*" >&2
}

skip() {
  log "skipping ${DEBIAN_PACKAGE}: $*"
  exit 2
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
        case "${part}" in
          abiword)
            native+="AbiWord"
            ;;
          *)
            native+="${part^}"
            ;;
        esac
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

command_name_allowed() {
  [[ "$1" =~ ^[A-Za-z0-9._+-]+$ ]]
}

libreoffice_mode_for_command() {
  case "$1" in
    libreoffice|loffice|soffice)
      printf '%s\n' ""
      ;;
    localc|scalc)
      printf '%s\n' "--calc"
      ;;
    lowriter|swriter)
      printf '%s\n' "--writer"
      ;;
    loimpress|simpress)
      printf '%s\n' "--impress"
      ;;
    lodraw|sdraw)
      printf '%s\n' "--draw"
      ;;
    lomath|smath)
      printf '%s\n' "--math"
      ;;
    lobase|sbase)
      printf '%s\n' "--base"
      ;;
    *)
      return 1
      ;;
  esac
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

if [[ "${AUZIX_TRIXIE_OVERWRITE_NATIVE:-0}" != "1" ]]; then
  while IFS= read -r existing_receipt; do
    existing_stage="$(jq -r '.migration_stage // empty' "${existing_receipt}")"
    existing_source_type="$(jq -r '.source.type // empty' "${existing_receipt}")"
    existing_source_package="$(jq -r '.source.package // empty' "${existing_receipt}")"
    if [[ "${existing_stage}" != "stage-1-auzix-native-repack" ||
      "${existing_source_type}" != "debian-binary-package" ||
      "${existing_source_package}" != "${package_name}" ]]; then
      skip "${native_name} already has a higher-trust receipt: ${existing_receipt#${AUZIX_ROOT}/}"
    fi
  done < <(
    find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
      -name "${native_name}-*.auzix.json" -print 2>/dev/null
  )
fi

dpkg-deb -x "${deb_path}" "${WORK_DIR}/extract"
rm -rf "${program_root}" "${legacy_program_root}"
rm -f "${receipt_path}" "${legacy_receipt_path}"
mkdir -p "${program_root}/RootFS" "${program_root}/Metadata" "${program_root}/Commands"
rsync -a "${WORK_DIR}/extract/" "${program_root}/RootFS/"
dpkg-deb -f "${deb_path}" >"${program_root}/Metadata/debian-control.txt"
ln -sfn "/Programs/${native_name}/${safe_version}" \
  "${AUZIX_ROOT}/Programs/${native_name}/current"
commands_json='[]'
compatibility_exports_json='[]'
while IFS= read -r rel_command; do
  command_base="$(basename "${rel_command}")"
  command_name_allowed "${command_base}" || continue
  [[ -x "${program_root}/RootFS/${rel_command}" ]] || continue
  if [[ "${native_name}" == LibreOffice* ]] &&
    libreoffice_mode="$(libreoffice_mode_for_command "${command_base}")"; then
    cat >"${program_root}/Commands/${command_base}" <<EOF
#!/Programs/BusyBox/current/Commands/busybox sh
set -eu
prefix="/Programs/${native_name}/current"
rootfs="\${prefix}/RootFS"
common="/Programs/LibreOfficeCommon/current/RootFS"
core="/Programs/LibreOfficeCore/current/RootFS"
export PATH="\${prefix}/Commands:\${rootfs}/usr/bin:\${common}/usr/bin:\${rootfs}/usr/sbin:\${rootfs}/bin:\${rootfs}/sbin:/Programs/BusyBox/current/Commands:/System/Compatibility/bin:/System/Compatibility/usr/bin\${PATH:+:\${PATH}}"
export XDG_DATA_DIRS="\${rootfs}/usr/share:\${common}/usr/share:/System/Compatibility/usr/share\${XDG_DATA_DIRS:+:\${XDG_DATA_DIRS}}"
export URE_BOOTSTRAP="vnd.sun.star.pathname:\${common}/usr/lib/libreoffice/program/fundamentalrc"
export UNO_PATH="\${common}/usr/lib/libreoffice/program"
export LD_LIBRARY_PATH="\${rootfs}/usr/lib/libreoffice/program:\${common}/usr/lib/libreoffice/program:\${core}/usr/lib/libreoffice/program:\${rootfs}/usr/lib/x86_64-linux-gnu:\${common}/usr/lib/x86_64-linux-gnu:\${core}/usr/lib/x86_64-linux-gnu:\${rootfs}/usr/lib:\${common}/usr/lib:\${core}/usr/lib:/Programs/Ure/current/RootFS/usr/lib/libreoffice/program:/Programs/UnoLibsPrivate/current/RootFS/usr/lib/libreoffice/program:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64:/System/Libraries\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
exec "\${common}/usr/lib/libreoffice/program/soffice" ${libreoffice_mode} "\$@"
EOF
  else
    cat >"${program_root}/Commands/${command_base}" <<EOF
#!/Programs/BusyBox/current/Commands/busybox sh
set -eu
prefix="/Programs/${native_name}/current"
rootfs="\${prefix}/RootFS"
export PATH="\${prefix}/Commands:\${rootfs}/usr/bin:\${rootfs}/usr/sbin:\${rootfs}/bin:\${rootfs}/sbin:/Programs/BusyBox/current/Commands:/System/Compatibility/bin:/System/Compatibility/usr/bin\${PATH:+:\${PATH}}"
export XDG_DATA_DIRS="\${rootfs}/usr/share:/System/Compatibility/usr/share\${XDG_DATA_DIRS:+:\${XDG_DATA_DIRS}}"
export GSETTINGS_SCHEMA_DIR="\${rootfs}/usr/share/glib-2.0/schemas\${GSETTINGS_SCHEMA_DIR:+:\${GSETTINGS_SCHEMA_DIR}}"
export LD_LIBRARY_PATH="\${rootfs}/usr/lib/x86_64-linux-gnu:\${rootfs}/usr/lib:\${rootfs}/lib/x86_64-linux-gnu:\${rootfs}/lib:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64:/System/Libraries\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
exec "\${rootfs}/${rel_command}" "\$@"
EOF
  fi
  chmod 0755 "${program_root}/Commands/${command_base}"
  mkdir -p "${AUZIX_ROOT}/System/Compatibility/bin" "${AUZIX_ROOT}/System/Compatibility/usr/bin"
  ln -sfn "/Programs/${native_name}/current/Commands/${command_base}" \
    "${AUZIX_ROOT}/System/Compatibility/bin/${command_base}"
  ln -sfn "/Programs/${native_name}/current/Commands/${command_base}" \
    "${AUZIX_ROOT}/System/Compatibility/usr/bin/${command_base}"
  commands_json="$(
    jq -cn --argjson current "${commands_json}" \
      --arg command "/Programs/${native_name}/${safe_version}/Commands/${command_base}" \
      '$current + [$command]'
  )"
  compatibility_exports_json="$(
    jq -cn --argjson current "${compatibility_exports_json}" \
      --arg bin "/System/Compatibility/bin/${command_base}" \
      --arg usrbin "/System/Compatibility/usr/bin/${command_base}" \
      '$current + [$bin, $usrbin]'
  )"
done < <(
  find "${program_root}/RootFS" -type f \
    \( -path '*/bin/*' -o -path '*/sbin/*' \) \
    -perm /111 \
    -printf '%P\n' |
    sort
)
payload_file_count="$(find "${program_root}/RootFS" -type f | wc -l | tr -d ' ')"
payload_size_bytes="$(du -sb "${program_root}/RootFS" | awk '{print $1}')"
command_count="$(jq 'length' <<<"${commands_json}")"
repack_class="payload"
if [[ "${payload_file_count}" -lt 25 && -n "${package_depends}" ]]; then
  repack_class="dependency-bundle"
fi
package_kind="program"
if [[ "${command_count}" -eq 0 ]]; then
  package_kind="staging"
fi

jq -n \
  --arg name "${native_name}" \
  --arg version "${safe_version}" \
  --arg kind "${package_kind}" \
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
  --argjson commands "${commands_json}" \
  --argjson compatibility_exports "${compatibility_exports_json}" \
  --argjson payload_file_count "${payload_file_count}" \
  --argjson payload_size_bytes "${payload_size_bytes}" \
  '{
    name: $name,
    version: $version,
    kind: $kind,
    migration_stage: "stage-1-auzix-native-repack",
    prefix: $prefix,
    paths: {prefix: $prefix, current: $current},
    depends: $depends,
    commands: $commands,
    compatibility_exports: $compatibility_exports,
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
    notes: "Experimental Trixie intake package. Debian payloads are staged under RootFS; detected executable payloads are exposed through AUZiX command wrappers. Packages without commands remain staging metadata until promoted."
  }' >"${receipt_path}"

log "built ${native_name} ${package_version} from ${package_name} (${repack_class}, ${payload_file_count} files, ${command_count} commands)"
