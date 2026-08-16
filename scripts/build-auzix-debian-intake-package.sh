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
      api|dns|gcc|gimp|gtk|html|http|ip|pdf|pip|ssh|ssl|ui|vim|vlc|x11|xcb|xfce|xml)
        native+="${part^^}"
        ;;
      cmake)
        native+="CMake"
        ;;
      dbus)
        native+="DBus"
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

if [[ "${1:-}" == "--print-native-name" ]]; then
  auzix_native_name "${2:?usage: build-auzix-debian-intake-package.sh --print-native-name <debian-package>}"
  exit 0
fi

clean_debian_dep_atom() {
  sed -E 's/[[:space:]]*\([^)]*\)//g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/:[A-Za-z0-9_-]+$//'
}

debian_package_has_candidate() {
  local package="$1"
  apt-cache policy "${package}" 2>/dev/null |
    awk '/Candidate:/ { if ($2 != "(none)") found = 1 } END { exit found ? 0 : 1 }'
}

auzix_dependency_alternative_score() {
  local package="$1"
  case "${package}" in
    opensysusers|systemd-standalone-sysusers|systemd-standalone-tmpfiles)
      printf '0\n'
      ;;
    systemd)
      printf '90\n'
      ;;
    *)
      printf '10\n'
      ;;
  esac
}

debian_depends_to_package_lines() {
  local depends_text="$1"
  local dep alternative clean selected selected_score score
  tr ',' '\n' <<<"${depends_text}" |
    while IFS= read -r dep; do
      selected=""
      selected_score=999
      while IFS= read -r alternative; do
        clean="$(clean_debian_dep_atom <<<"${alternative}")"
        [[ "${clean}" =~ ^[a-z0-9][a-z0-9+_.-]*$ ]] || continue
        if debian_package_has_candidate "${clean}"; then
          score="$(auzix_dependency_alternative_score "${clean}")"
          if [[ "${score}" -lt "${selected_score}" ]]; then
            selected="${clean}"
            selected_score="${score}"
          fi
          continue
        fi
        [[ -n "${selected}" ]] || selected="${clean}"
      done < <(tr '|' '\n' <<<"${dep}")
      [[ -n "${selected}" ]] || continue
      if ! debian_package_has_candidate "${selected}"; then
        log "skipping virtual/no-candidate dependency ${selected}"
        continue
      fi
      printf '%s\n' "${selected}"
    done | awk '!seen[$0]++'
}

debian_depends_to_native_json() {
  local depends_text="$1"
  local dep native
  {
    debian_depends_to_package_lines "${depends_text}" |
      while IFS= read -r dep; do
        native="$(auzix_native_name "${dep}")"
        [[ -n "${native}" ]] || continue
        printf '%s\n' "${native}"
      done | awk '!seen[$0]++'
  } | jq -R -s 'split("\n") | map(select(length > 0))'
}

native_receipt_exists() {
  local native="$1"
  find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
    -name "${native}-*.auzix.json" -print -quit 2>/dev/null | grep -q .
}

build_missing_debian_dependencies() {
  local depends_text="$1"
  local package dep dep_native next_depth
  local depth="${AUZIX_TRIXIE_DEP_DEPTH:-0}"
  local max_depth="${AUZIX_TRIXIE_DEP_MAX_DEPTH:-64}"
  local stack=" ${AUZIX_TRIXIE_DEP_STACK:-} ${package_name} "
  [[ "${AUZIX_TRIXIE_BUILD_DEPENDS:-1}" == "1" ]] || return 0
  [[ "${depth}" -lt "${max_depth}" ]] || {
    log "dependency recursion depth ${depth} reached max ${max_depth}; continuing with current receipts"
    return 0
  }
  next_depth="$((depth + 1))"
  log "dependency scan for ${package_name}: depth=${depth} max=${max_depth}"
  while IFS= read -r dep; do
    [[ -n "${dep}" ]] || continue
    [[ "${dep}" != "${package_name}" ]] || continue
    if [[ "${stack}" == *" ${dep} "* ]]; then
      log "skipping dependency cycle ${package_name} -> ${dep}"
      continue
    fi
    dep_native="$(auzix_native_name "${dep}")"
    if native_receipt_exists "${dep_native}"; then
      log "dependency already staged ${dep} -> ${dep_native}"
      continue
    fi
    log "building missing dependency ${dep} -> ${dep_native} for ${package_name}"
    AUZIX_TRIXIE_DEP_DEPTH="${next_depth}" \
    AUZIX_TRIXIE_DEP_STACK="${AUZIX_TRIXIE_DEP_STACK:-} ${package_name}" \
    AUZIX_TRIXIE_BUILD_DEPENDS="${AUZIX_TRIXIE_BUILD_DEPENDS:-1}" \
    AUZIX_TRIXIE_INCLUDE_RECOMMENDS="${AUZIX_TRIXIE_INCLUDE_RECOMMENDS:-0}" \
    AUZIX_TRIXIE_OVERWRITE_NATIVE="${AUZIX_TRIXIE_OVERWRITE_NATIVE:-0}" \
      "${BASH_SOURCE[0]}" "${AUZIX_ROOT}" "${dep}" || {
        log "dependency build failed for ${dep}; ${package_name} may fail validation"
        return 1
      }
  done < <(debian_depends_to_package_lines "${depends_text}")
}

debian_control_field() {
  local control_file="$1"
  local field_name="$2"
  awk -v field="${field_name}" '
    BEGIN { in_field = 0 }
    $0 ~ "^" field ":" {
      in_field = 1
      sub("^[^:]+:[[:space:]]*", "")
      print
      next
    }
    /^[^[:space:]]/ {
      in_field = 0
      next
    }
    in_field && /^[[:space:]]/ {
      sub("^[[:space:]]+", "")
      print
    }
  ' "${control_file}" | paste -sd' ' -
}

native_installed_depends_closure_words() {
  local roots_text="$1"
  local package_db="$2"
  local roots_json
  roots_json="$(tr ' ' '\n' <<<"${roots_text}" | awk 'NF && !seen[$0]++' | jq -R -s 'split("\n") | map(select(length > 0))')"
  python3 - "${package_db}" "${roots_json}" <<'PY'
import json
import pathlib
import sys

package_db = pathlib.Path(sys.argv[1])
roots = json.loads(sys.argv[2])
receipts = {}

if package_db.is_dir():
    for receipt_path in package_db.glob("*.json"):
        try:
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        except Exception:
            continue
        name = receipt.get("name")
        if name:
            receipts[name] = receipt

ordered = []
seen = set()
stack = list(reversed(roots))
while stack:
    name = stack.pop()
    if name in seen:
        continue
    seen.add(name)
    ordered.append(name)
    receipt = receipts.get(name)
    if not receipt:
        continue
    depends = receipt.get("depends") or []
    for dep in reversed(depends):
        if dep and dep not in seen:
            stack.append(dep)

print(" ".join(ordered))
PY
}

command_name_allowed() {
  [[ "$1" =~ ^[A-Za-z0-9._+-]+$ ]]
}

rewrite_common_payload_paths() {
  local payload_root="$1"
  while IFS= read -r text_path; do
    sed -i \
      -e '1s@^#!/bin/sh@#!/Programs/BusyBox/current/Commands/busybox sh@' \
      -e '1s@^#!/usr/bin/env sh@#!/Programs/BusyBox/current/Commands/busybox sh@' \
      -e '1s@^#!/bin/bash@#!/Programs/Bash/current/Commands/bash@' \
      -e '1s@^#!/usr/bin/env bash@#!/Programs/Bash/current/Commands/bash@' \
      -e 's#^\(Exec=\)/usr/bin/#\1/System/Compatibility/bin/#' \
      -e 's#^\(Exec=\)/usr/sbin/#\1/System/Compatibility/sbin/#' \
      -e 's#^\(Exec=\)/bin/#\1/System/Compatibility/bin/#' \
      -e 's#^\(Exec=\)/sbin/#\1/System/Compatibility/sbin/#' \
      -e 's#\([[:space:]]\)/usr/bin/#\1/System/Compatibility/bin/#g' \
      -e 's#\([[:space:]]\)/usr/sbin/#\1/System/Compatibility/sbin/#g' \
      -e 's#\([[:space:]]\)/bin/#\1/System/Compatibility/bin/#g' \
      -e 's#\([[:space:]]\)/sbin/#\1/System/Compatibility/sbin/#g' \
      "${text_path}"
  done < <(
    find "${payload_root}" -type f \
      \( -path '*/usr/share/dbus-1/services/*.service' \
        -o -path '*/usr/lib/systemd/system/*.service' \
        -o -path '*/usr/lib/systemd/user/*.service' \
        -o -path '*/usr/share/applications/*.desktop' \
        -o -perm /111 \) \
      -exec grep -IlE '/usr/bin|/usr/sbin|/bin/|/sbin/|^#!/bin/sh|^#!/bin/bash|^#!/usr/bin/env (ba)?sh' {} + 2>/dev/null
  )
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
chmod 0755 "${ROOT_DIR}/out" "${ROOT_DIR}/out/auzix-packages" \
  "${ROOT_DIR}/out/auzix-packages/trixie" "${WORK_DIR}" "${WORK_DIR}/debs" \
  "${WORK_DIR}/extract" 2>/dev/null || true
(
  cd "${WORK_DIR}/debs"
  apt-get -o APT::Sandbox::User=root download "${DEBIAN_PACKAGE}" >/dev/null
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
package_predepends="$(dpkg-deb -f "${deb_path}" Pre-Depends 2>/dev/null || true)"
package_depends="$(dpkg-deb -f "${deb_path}" Depends 2>/dev/null || true)"
package_recommends="$(dpkg-deb -f "${deb_path}" Recommends 2>/dev/null || true)"
dependency_contract="${package_predepends}${package_predepends:+, }${package_depends}"
if [[ "${AUZIX_TRIXIE_INCLUDE_RECOMMENDS:-0}" == "1" && -n "${package_recommends}" ]]; then
  dependency_contract="${dependency_contract}${dependency_contract:+, }${package_recommends}"
fi
build_missing_debian_dependencies "${dependency_contract}"
native_depends_json="$(debian_depends_to_native_json "${dependency_contract}")"
native_recommends_json="$(debian_depends_to_native_json "${package_recommends}")"
native_depends_words="$(jq -r 'join(" ")' <<<"${native_depends_json}")"
safe_version="$(tr '/: ' '---' <<<"${package_version}" | tr -cd 'A-Za-z0-9_.+~-')"
native_name="$(auzix_native_name "${package_name}")"
if [[ "${native_name}" == LibreOffice* && "${native_name}" != "LibreOfficeCore" ]]; then
  core_control="$(find "${AUZIX_ROOT}/Programs/LibreOfficeCore" -mindepth 3 -maxdepth 3 -path '*/Metadata/debian-control.txt' -print 2>/dev/null | sort | tail -n 1 || true)"
  if [[ -n "${core_control}" && -s "${core_control}" ]]; then
    core_depends="$(debian_control_field "${core_control}" Depends)"
    if [[ -n "${core_depends}" ]]; then
      core_depends_words="$(debian_depends_to_native_json "${core_depends}" | jq -r 'join(" ")')"
      native_depends_words="$(tr ' ' '\n' <<<"${native_depends_words} LibreOfficeCore ${core_depends_words}" | awk 'NF && !seen[$0]++' | paste -sd' ' -)"
      native_depends_json="$(tr ' ' '\n' <<<"${native_depends_words}" | jq -R -s 'split("\n") | map(select(length > 0))')"
    fi
  fi
fi
native_depends_words="$(native_installed_depends_closure_words "${native_depends_words}" "${AUZIX_ROOT}/System/PackageDB")"
native_depends_json="$(tr ' ' '\n' <<<"${native_depends_words}" | jq -R -s 'split("\n") | map(select(length > 0))')"
validation_library_paths_json="$(
  {
    printf '/Programs/%s/%s/RootFS/usr/lib/x86_64-linux-gnu\n' "${native_name:-UNKNOWN}" "${safe_version:-UNKNOWN}"
    printf '/Programs/%s/%s/RootFS/usr/lib\n' "${native_name:-UNKNOWN}" "${safe_version:-UNKNOWN}"
    printf '/Programs/%s/%s/RootFS/lib/x86_64-linux-gnu\n' "${native_name:-UNKNOWN}" "${safe_version:-UNKNOWN}"
    printf '/Programs/%s/%s/RootFS/lib\n' "${native_name:-UNKNOWN}" "${safe_version:-UNKNOWN}"
    tr ' ' '\n' <<<"${native_depends_words}" |
      while IFS= read -r runtime_package; do
        [[ -n "${runtime_package}" ]] || continue
        printf '/Programs/%s/current/RootFS/usr/lib/x86_64-linux-gnu\n' "${runtime_package}"
        printf '/Programs/%s/current/RootFS/usr/lib\n' "${runtime_package}"
        printf '/Programs/%s/current/RootFS/lib/x86_64-linux-gnu\n' "${runtime_package}"
        printf '/Programs/%s/current/RootFS/lib\n' "${runtime_package}"
      done
    printf '/System/Compatibility/usr/lib/x86_64-linux-gnu\n'
    printf '/System/Compatibility/lib/x86_64-linux-gnu\n'
    printf '/System/Compatibility/lib64\n'
    printf '/System/Libraries\n'
  } | awk '!seen[$0]++' | jq -R -s 'split("\n") | map(select(length > 0))'
)"
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
rm -rf "${WORK_DIR}/control"
mkdir -p "${WORK_DIR}/control"
dpkg-deb -e "${deb_path}" "${WORK_DIR}/control" 2>/dev/null || true
rm -rf "${program_root}" "${legacy_program_root}"
rm -f "${receipt_path}" "${legacy_receipt_path}"
mkdir -p "${program_root}/RootFS" "${program_root}/Metadata" "${program_root}/Commands"
rsync -a "${WORK_DIR}/extract/" "${program_root}/RootFS/"
if [[ -d "${WORK_DIR}/control" ]]; then
  rsync -a "${WORK_DIR}/control/" "${program_root}/Metadata/debian-control-dir/"
fi
rewrite_common_payload_paths "${program_root}/RootFS"
if [[ "${native_name}" == LibreOffice* ]]; then
  rm -rf "${program_root}/RootFS/etc/apparmor.d"
  while IFS= read -r libreoffice_text; do
    sed -i \
      -e 's#file:///usr/lib/libreoffice#file:///System/State/libreoffice#g' \
      -e 's#file:///etc/libreoffice#file:///System/Settings/libreoffice#g' \
      -e 's#/usr/lib/libreoffice/program#/System/State/libreoffice/program#g' \
      -e 's#/usr/lib/libreoffice#/System/State/libreoffice#g' \
      -e 's#/etc/libreoffice#/System/Settings/libreoffice#g' \
      "${libreoffice_text}"
  done < <(
    find "${program_root}/RootFS" -type f \
      \( -path '*/usr/bin/*' -o -path '*/usr/lib/libreoffice/program/*' -o -path '*/usr/share/libreoffice/*' \) \
      -exec grep -Il '/usr/lib/libreoffice' {} + 2>/dev/null
  )
  while IFS= read -r libreoffice_link; do
    link_target="$(readlink "${libreoffice_link}" || true)"
    case "${link_target}" in
      /etc/libreoffice/registry/main.xcd)
        rm -f "${libreoffice_link}"
        ln -s ../.registry/main.xcd "${libreoffice_link}"
        ;;
      /etc/libreoffice/*)
        rm -f "${libreoffice_link}"
        ln -s "/System/Settings/libreoffice/${link_target#/etc/libreoffice/}" "${libreoffice_link}"
        ;;
      /usr/lib/libreoffice/*)
        rm -f "${libreoffice_link}"
        ln -s "/System/State/libreoffice/${link_target#/usr/lib/libreoffice/}" "${libreoffice_link}"
        ;;
    esac
  done < <(find "${program_root}/RootFS" -type l -print)
fi
dpkg-deb -f "${deb_path}" >"${program_root}/Metadata/debian-control.txt"
dpkg-deb -c "${deb_path}" |
  awk '
    {
      path = $NF
      sub(/^\.\//, "", path)
      if (path != "." && path != "") print "/" path
    }
  ' | sort -u >"${program_root}/Metadata/debian-payload.list"
if [[ -s "${program_root}/Metadata/debian-control-dir/md5sums" ]]; then
  cp -f "${program_root}/Metadata/debian-control-dir/md5sums" \
    "${program_root}/Metadata/debian-payload.md5sums"
else
  : >"${program_root}/Metadata/debian-payload.md5sums"
fi
maintainer_surfaces_json="$(
  if [[ -d "${program_root}/Metadata/debian-control-dir" ]]; then
    find "${program_root}/Metadata/debian-control-dir" -maxdepth 1 -type f \
      \( -name 'preinst' -o -name 'postinst' -o -name 'prerm' -o -name 'postrm' \
        -o -name 'triggers' -o -name 'conffiles' -o -name 'config' -o -name 'templates' \) \
      -printf '%f\n' |
      awk -v native_name="${native_name}" -v safe_version="${safe_version}" \
        '{ printf "/Programs/%s/%s/Metadata/debian-control-dir/%s\n", native_name, safe_version, $0 }' |
      sort | jq -R -s 'split("\n") | map(select(length > 0))'
  else
    jq -n '[]'
  fi
)"
debian_payload_manifest_json="$(
  jq -Rn '
    [inputs | select(length > 0) |
      {
        debian_path: .,
        auzix_payload_path: ("RootFS" + .),
        owner_source: "debian archive data.tar / dpkg -L equivalent"
      }]
  ' <"${program_root}/Metadata/debian-payload.list"
)"
debian_md5sums_json="$(
  awk '
    NF >= 2 {
      checksum = $1
      $1 = ""
      sub(/^[[:space:]]+/, "")
      print checksum "\t/" $0
    }
  ' "${program_root}/Metadata/debian-payload.md5sums" |
    jq -Rn '
      [inputs | select(length > 0) |
        split("\t") |
        {
          md5: .[0],
          debian_path: .[1],
          auzix_payload_path: ("RootFS" + .[1])
        }]
    '
)"
ln -sfn "/Programs/${native_name}/${safe_version}" \
  "${AUZIX_ROOT}/Programs/${native_name}/current"
commands_json='[]'
compatibility_exports_json='[]'
mkdir -p "${AUZIX_ROOT}/System/Compatibility/usr/share/applications"
while IFS= read -r rel_command; do
  command_base="$(basename "${rel_command}")"
  command_name_allowed "${command_base}" || continue
  [[ -x "${program_root}/RootFS/${rel_command}" ]] || continue
  if [[ "${native_name}" == LibreOffice* ]] &&
    libreoffice_mode="$(libreoffice_mode_for_command "${command_base}")"; then
    cat >"${program_root}/Commands/${command_base}" <<EOF
#!/Programs/BusyBox/current/Commands/busybox sh
set -eu
BB="/Programs/BusyBox/current/Commands/busybox"
prefix="/Programs/${native_name}/current"
rootfs="\${prefix}/RootFS"
common="/Programs/LibreOfficeCommon/current/RootFS"
core="/Programs/LibreOfficeCore/current/RootFS"
state="\${XDG_CACHE_HOME:-\${HOME:-/Users/root}/.cache}/auzix-libreoffice"
settings="\${XDG_CONFIG_HOME:-\${HOME:-/Users/root}/.config}/auzix-libreoffice-settings"
program="\${state}/program"
share="\${state}/share"
presets="\${state}/presets"
runtime_packages="${native_depends_words}"
runtime_lib_path=""
font_dirs=""
lo_share_roots="\${common}/usr/lib/libreoffice/share \${common}/usr/share/libreoffice \${rootfs}/usr/lib/libreoffice/share \${rootfs}/usr/share/libreoffice"
lo_preset_roots="\${common}/usr/lib/libreoffice/presets \${rootfs}/usr/lib/libreoffice/presets"
lo_settings_roots="\${common}/etc/libreoffice \${rootfs}/etc/libreoffice"
"\${BB}" mkdir -p "\${program}" "\${share}" "\${presets}" "\${settings}"
for runtime_package in \${runtime_packages}; do
  runtime_root="/Programs/\${runtime_package}/current/RootFS"
  [ -d "\${runtime_root}" ] || continue
  [ -d "\${runtime_root}/usr/lib/x86_64-linux-gnu" ] && runtime_lib_path="\${runtime_lib_path}:\${runtime_root}/usr/lib/x86_64-linux-gnu"
  [ -d "\${runtime_root}/lib/x86_64-linux-gnu" ] && runtime_lib_path="\${runtime_lib_path}:\${runtime_root}/lib/x86_64-linux-gnu"
  [ -d "\${runtime_root}/usr/lib" ] && runtime_lib_path="\${runtime_lib_path}:\${runtime_root}/usr/lib"
  [ -d "\${runtime_root}/lib" ] && runtime_lib_path="\${runtime_lib_path}:\${runtime_root}/lib"
  [ -d "\${runtime_root}/usr/share/fonts" ] && font_dirs="\${font_dirs} \${runtime_root}/usr/share/fonts"
  [ -d "\${runtime_root}/usr/lib/libreoffice/share" ] && lo_share_roots="\${lo_share_roots} \${runtime_root}/usr/lib/libreoffice/share"
  [ -d "\${runtime_root}/usr/share/libreoffice" ] && lo_share_roots="\${lo_share_roots} \${runtime_root}/usr/share/libreoffice"
  [ -d "\${runtime_root}/usr/lib/libreoffice/presets" ] && lo_preset_roots="\${lo_preset_roots} \${runtime_root}/usr/lib/libreoffice/presets"
  [ -d "\${runtime_root}/etc/libreoffice" ] && lo_settings_roots="\${lo_settings_roots} \${runtime_root}/etc/libreoffice"
done
for source_dir in \\
  "\${common}/usr/lib/libreoffice/program" \\
  "\${core}/usr/lib/libreoffice/program" \\
  "\${rootfs}/usr/lib/libreoffice/program" \\
  "/Programs/Ure/current/RootFS/usr/lib/libreoffice/program" \\
  "/Programs/UnoLibsPrivate/current/RootFS/usr/lib/libreoffice/program" \\
  "/Programs/LibunoSal3t64/current/RootFS/usr/lib/libreoffice/program" \\
  "/Programs/LibunoCppu3t64/current/RootFS/usr/lib/libreoffice/program" \\
  "/Programs/LibunoCppuhelpergcc33t64/current/RootFS/usr/lib/libreoffice/program" \\
  "/Programs/LibunoSalhelpergcc33t64/current/RootFS/usr/lib/libreoffice/program" \\
  "/Programs/LibunoPurpenvhelpergcc33t64/current/RootFS/usr/lib/libreoffice/program"; do
  [ -d "\${source_dir}" ] || continue
  for item in "\${source_dir}"/*; do
    [ -e "\${item}" ] || continue
    item_base="\$("\${BB}" basename "\${item}")"
    if [ "\${item_base}" = "soffice" ]; then
      "\${BB}" cp "\${item}" "\${program}/\${item_base}"
      "\${BB}" chmod 0755 "\${program}/\${item_base}"
    else
      "\${BB}" ln -sfn "\${item}" "\${program}/\${item_base}"
    fi
  done
done
if [ -e "\${program}/fundamentalrc" ]; then
  if [ -L "\${program}/fundamentalrc" ]; then
    fundamental_source="\$("${BB}" readlink "\${program}/fundamentalrc")"
    "\${BB}" rm -f "\${program}/fundamentalrc"
    "\${BB}" cp "\${fundamental_source}" "\${program}/fundamentalrc"
  fi
  "\${BB}" sed -i 's#^BRAND_BASE_DIR=.*#BRAND_BASE_DIR=\${ORIGIN}/..#' "\${program}/fundamentalrc"
fi
for source_dir in \${lo_share_roots}; do
  [ -d "\${source_dir}" ] || continue
  (cd "\${source_dir}" && "\${BB}" find . -type d -print) | while IFS= read -r rel_dir; do
    [ "\${rel_dir}" = "." ] && continue
    [ -L "\${share}/\${rel_dir#./}" ] && "\${BB}" rm "\${share}/\${rel_dir#./}"
    "\${BB}" mkdir -p "\${share}/\${rel_dir#./}"
  done
  (cd "\${source_dir}" && "\${BB}" find . \( -type f -o -type l \) -print) | while IFS= read -r rel_item; do
    target_dir="\${share}/\$("\${BB}" dirname "\${rel_item#./}")"
    [ "\${target_dir}" = "\${share}/." ] && target_dir="\${share}"
    "\${BB}" mkdir -p "\${target_dir}"
    "\${BB}" ln -sfn "\${source_dir}/\${rel_item#./}" "\${share}/\${rel_item#./}"
  done
done
for source_dir in \${lo_preset_roots}; do
  [ -d "\${source_dir}" ] || continue
  (cd "\${source_dir}" && "\${BB}" find . -type d -print) | while IFS= read -r rel_dir; do
    [ "\${rel_dir}" = "." ] && continue
    [ -L "\${presets}/\${rel_dir#./}" ] && "\${BB}" rm "\${presets}/\${rel_dir#./}"
    "\${BB}" mkdir -p "\${presets}/\${rel_dir#./}"
  done
  (cd "\${source_dir}" && "\${BB}" find . \( -type f -o -type l \) -print) | while IFS= read -r rel_item; do
    target_dir="\${presets}/\$("\${BB}" dirname "\${rel_item#./}")"
    [ "\${target_dir}" = "\${presets}/." ] && target_dir="\${presets}"
    "\${BB}" mkdir -p "\${target_dir}"
    "\${BB}" ln -sfn "\${source_dir}/\${rel_item#./}" "\${presets}/\${rel_item#./}"
  done
done
for source_dir in \${lo_settings_roots}; do
  [ -d "\${source_dir}" ] || continue
  (cd "\${source_dir}" && "\${BB}" find . -type d -print) | while IFS= read -r rel_dir; do
    [ "\${rel_dir}" = "." ] && continue
    [ -L "\${settings}/\${rel_dir#./}" ] && "\${BB}" rm "\${settings}/\${rel_dir#./}"
    "\${BB}" mkdir -p "\${settings}/\${rel_dir#./}"
  done
  (cd "\${source_dir}" && "\${BB}" find . \( -type f -o -type l \) -print) | while IFS= read -r rel_item; do
    target_dir="\${settings}/\$("\${BB}" dirname "\${rel_item#./}")"
    [ "\${target_dir}" = "\${settings}/." ] && target_dir="\${settings}"
    "\${BB}" mkdir -p "\${target_dir}"
    "\${BB}" ln -sfn "\${source_dir}/\${rel_item#./}" "\${settings}/\${rel_item#./}"
  done
done
export HOME="\${HOME:-/Users/root}"
if [ "\${HOME}" = "/root" ]; then
  export HOME="/Users/root"
fi
export XDG_CONFIG_HOME="\${XDG_CONFIG_HOME:-\${HOME}/.config}"
export USER="\${USER:-root}"
export LOGNAME="\${LOGNAME:-\${USER}}"
export TMPDIR="\${TMPDIR:-/Work/Temp}"
"\${BB}" mkdir -p "\${HOME}" "\${XDG_CONFIG_HOME}" "\${TMPDIR}" "\${XDG_CONFIG_HOME}/libreoffice/4/user"
if [ -n "\${font_dirs}" ]; then
  "\${BB}" mkdir -p "\${XDG_CONFIG_HOME}/fontconfig" "\${HOME}/.cache/fontconfig"
  {
    echo '<?xml version="1.0"?>'
    echo '<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">'
    echo '<fontconfig>'
    for font_dir in \${font_dirs}; do
      echo "  <dir>\${font_dir}</dir>"
    done
    echo "  <cachedir>\${HOME}/.cache/fontconfig</cachedir>"
    echo '</fontconfig>'
  } >"\${XDG_CONFIG_HOME}/fontconfig/fonts.conf"
  export FONTCONFIG_FILE="\${XDG_CONFIG_HOME}/fontconfig/fonts.conf"
  export FONTCONFIG_PATH="\${XDG_CONFIG_HOME}/fontconfig"
fi
export PATH="\${prefix}/Commands:\${rootfs}/usr/bin:\${common}/usr/bin:\${rootfs}/usr/sbin:\${rootfs}/bin:\${rootfs}/sbin:/Programs/BusyBox/current/Commands:/System/Compatibility/bin:/System/Compatibility/usr/bin:/System/Compatibility/sbin:/System/Compatibility/usr/sbin\${PATH:+:\${PATH}}"
export XDG_DATA_DIRS="\${rootfs}/usr/share:\${common}/usr/share:/System/Compatibility/usr/share\${XDG_DATA_DIRS:+:\${XDG_DATA_DIRS}}"
export URE_BOOTSTRAP="vnd.sun.star.pathname:\${program}/fundamentalrc"
export UNO_PATH="\${program}"
export LD_LIBRARY_PATH="\${program}:\${rootfs}/usr/lib/x86_64-linux-gnu:\${common}/usr/lib/x86_64-linux-gnu:\${core}/usr/lib/x86_64-linux-gnu:\${rootfs}/usr/lib:\${common}/usr/lib:\${core}/usr/lib\${runtime_lib_path}:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/usr/lib:/System/Compatibility/lib:/System/Compatibility/lib64:/System/Libraries\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
runtime_loader=""
for candidate_loader in \
  "/Programs/Libc6/current/RootFS/usr/lib64/ld-linux-x86-64.so.2" \
  "/Programs/Libc6/current/RootFS/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2" \
  "/Programs/Libc6/current/RootFS/lib64/ld-linux-x86-64.so.2" \
  "/Programs/Libc6/current/RootFS/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"; do
  if [ -x "\${candidate_loader}" ]; then
    runtime_loader="\${candidate_loader}"
    break
  fi
done
user_installation_arg=""
case "${libreoffice_mode}" in
  --impress)
    user_installation_arg="-env:UserInstallation=file://\${XDG_CONFIG_HOME}/libreoffice-impress"
    exec "\${program}/simpress" "\${user_installation_arg}" "\$@"
    ;;
  --draw)
    user_installation_arg="-env:UserInstallation=file://\${XDG_CONFIG_HOME}/libreoffice-draw"
    exec "\${program}/sdraw" "\${user_installation_arg}" "\$@"
    ;;
  *)
    exec "\${program}/soffice" ${libreoffice_mode} "\$@"
    ;;
esac
EOF
  else
    command_loader_tail='if [ -n "${runtime_loader}" ]; then
  exec "${runtime_loader}" --library-path "${LD_LIBRARY_PATH}" "${rootfs}/'"${rel_command}"'" "$@"
fi
exec "${rootfs}/'"${rel_command}"'" "$@"'
    if ! head -c 4 "${program_root}/RootFS/${rel_command}" | grep -q "$(printf '\177ELF')" 2>/dev/null; then
      command_loader_tail='exec "${rootfs}/'"${rel_command}"'" "$@"'
    fi
    cat >"${program_root}/Commands/${command_base}" <<EOF
#!/Programs/BusyBox/current/Commands/busybox sh
set -eu
prefix="/Programs/${native_name}/current"
rootfs="\${prefix}/RootFS"
runtime_packages="${native_depends_words}"
runtime_bin_path=""
runtime_data_path=""
runtime_schema_path=""
runtime_gi_path=""
runtime_lib_path=""
runtime_loader=""
append_existing_path() {
  variable_name="\$1"
  candidate_path="\$2"
  [ -d "\${candidate_path}" ] || return 0
  eval "current_value=\\\${\${variable_name}:-}"
  case ":\${current_value}:" in
    *":\${candidate_path}:"*) return 0 ;;
  esac
  if [ -n "\${current_value}" ]; then
    eval "\${variable_name}=\\\${current_value}:\${candidate_path}"
  else
    eval "\${variable_name}=\${candidate_path}"
  fi
}
for runtime_package in \${runtime_packages}; do
  runtime_root="/Programs/\${runtime_package}/current/RootFS"
  [ -d "\${runtime_root}" ] || continue
  append_existing_path runtime_bin_path "\${runtime_root}/usr/bin"
  append_existing_path runtime_bin_path "\${runtime_root}/usr/sbin"
  append_existing_path runtime_bin_path "\${runtime_root}/bin"
  append_existing_path runtime_bin_path "\${runtime_root}/sbin"
  append_existing_path runtime_data_path "\${runtime_root}/usr/share"
  append_existing_path runtime_schema_path "\${runtime_root}/usr/share/glib-2.0/schemas"
  append_existing_path runtime_gi_path "\${runtime_root}/usr/lib/x86_64-linux-gnu/girepository-1.0"
  append_existing_path runtime_gi_path "\${runtime_root}/usr/lib/girepository-1.0"
  append_existing_path runtime_lib_path "\${runtime_root}/usr/lib/x86_64-linux-gnu"
  append_existing_path runtime_lib_path "\${runtime_root}/usr/lib"
  append_existing_path runtime_lib_path "\${runtime_root}/lib/x86_64-linux-gnu"
  append_existing_path runtime_lib_path "\${runtime_root}/lib"
  if [ -z "\${runtime_loader}" ]; then
    for candidate_loader in \
      "\${runtime_root}/usr/lib64/ld-linux-x86-64.so.2" \
      "\${runtime_root}/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2" \
      "\${runtime_root}/lib64/ld-linux-x86-64.so.2" \
      "\${runtime_root}/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"; do
      if [ -x "\${candidate_loader}" ]; then
        runtime_loader="\${candidate_loader}"
        break
      fi
    done
  fi
done
if [ -d /Programs ]; then
  for runtime_root in /Programs/*/current/RootFS; do
    [ -d "\${runtime_root}" ] || continue
    append_existing_path runtime_lib_path "\${runtime_root}/usr/lib/x86_64-linux-gnu"
    append_existing_path runtime_lib_path "\${runtime_root}/usr/lib"
    append_existing_path runtime_lib_path "\${runtime_root}/lib/x86_64-linux-gnu"
    append_existing_path runtime_lib_path "\${runtime_root}/lib"
  done
fi
own_bin_path=""
own_data_path=""
own_schema_path=""
own_gi_path=""
own_lib_path=""
append_existing_path own_bin_path "\${prefix}/Commands"
append_existing_path own_bin_path "\${rootfs}/usr/bin"
append_existing_path own_bin_path "\${rootfs}/usr/sbin"
append_existing_path own_bin_path "\${rootfs}/bin"
append_existing_path own_bin_path "\${rootfs}/sbin"
append_existing_path own_data_path "\${rootfs}/usr/share"
append_existing_path own_schema_path "\${rootfs}/usr/share/glib-2.0/schemas"
append_existing_path own_gi_path "\${rootfs}/usr/lib/x86_64-linux-gnu/girepository-1.0"
append_existing_path own_gi_path "\${rootfs}/usr/lib/girepository-1.0"
append_existing_path own_lib_path "\${prefix}/Libraries"
append_existing_path own_lib_path "\${rootfs}/usr/lib/x86_64-linux-gnu"
append_existing_path own_lib_path "\${rootfs}/usr/lib"
append_existing_path own_lib_path "\${rootfs}/lib/x86_64-linux-gnu"
append_existing_path own_lib_path "\${rootfs}/lib"
append_existing_path own_lib_path "/System/Compatibility/usr/lib/x86_64-linux-gnu"
append_existing_path own_lib_path "/System/Compatibility/lib/x86_64-linux-gnu"
append_existing_path own_lib_path "/System/Compatibility/lib64"
append_existing_path own_lib_path "/System/Libraries"
export PATH="\${own_bin_path}\${runtime_bin_path:+:\${runtime_bin_path}}:/Programs/BusyBox/current/Commands:/System/Compatibility/bin:/System/Compatibility/usr/bin:/System/Compatibility/sbin:/System/Compatibility/usr/sbin\${PATH:+:\${PATH}}"
export XDG_DATA_DIRS="\${own_data_path}\${runtime_data_path:+:\${runtime_data_path}}:/System/Compatibility/usr/share\${XDG_DATA_DIRS:+:\${XDG_DATA_DIRS}}"
export GSETTINGS_SCHEMA_DIR="\${own_schema_path}\${runtime_schema_path:+:\${runtime_schema_path}}\${GSETTINGS_SCHEMA_DIR:+:\${GSETTINGS_SCHEMA_DIR}}"
export GI_TYPELIB_PATH="\${own_gi_path}\${runtime_gi_path:+:\${runtime_gi_path}}\${GI_TYPELIB_PATH:+:\${GI_TYPELIB_PATH}}"
export LD_LIBRARY_PATH="\${own_lib_path}\${runtime_lib_path:+:\${runtime_lib_path}}\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
${command_loader_tail}
EOF
  fi
  chmod 0755 "${program_root}/Commands/${command_base}"
  mkdir -p "${AUZIX_ROOT}/System/Compatibility/bin" \
    "${AUZIX_ROOT}/System/Compatibility/usr/bin" \
    "${AUZIX_ROOT}/System/Compatibility/sbin" \
    "${AUZIX_ROOT}/System/Compatibility/usr/sbin"
  ln -sfn "/Programs/${native_name}/current/Commands/${command_base}" \
    "${AUZIX_ROOT}/System/Compatibility/bin/${command_base}"
  ln -sfn "/Programs/${native_name}/current/Commands/${command_base}" \
    "${AUZIX_ROOT}/System/Compatibility/usr/bin/${command_base}"
  ln -sfn "/Programs/${native_name}/current/Commands/${command_base}" \
    "${AUZIX_ROOT}/System/Compatibility/sbin/${command_base}"
  ln -sfn "/Programs/${native_name}/current/Commands/${command_base}" \
    "${AUZIX_ROOT}/System/Compatibility/usr/sbin/${command_base}"
  commands_json="$(
    jq -cn --argjson current "${commands_json}" \
      --arg command "/Programs/${native_name}/${safe_version}/Commands/${command_base}" \
      '$current + [$command]'
  )"
  compatibility_exports_json="$(
    jq -cn --argjson current "${compatibility_exports_json}" \
      --arg bin "/System/Compatibility/bin/${command_base}" \
      --arg usrbin "/System/Compatibility/usr/bin/${command_base}" \
      --arg sbin "/System/Compatibility/sbin/${command_base}" \
      --arg usrsbin "/System/Compatibility/usr/sbin/${command_base}" \
      '$current + [$bin, $usrbin, $sbin, $usrsbin]'
  )"
done < <(
  find "${program_root}/RootFS" -type f \
    \( -path '*/bin/*' -o -path '*/sbin/*' \) \
    -perm /111 \
    -printf '%P\n' |
    sort
)
while IFS= read -r rel_desktop; do
  desktop_base="$(basename "${rel_desktop}")"
  command_name_allowed "${desktop_base}" || continue
  desktop_target="${AUZIX_ROOT}/System/Compatibility/usr/share/applications/auzix-${native_name}-${desktop_base}"
  desktop_exec_name="$(jq -r '.[0] // empty | split("/")[-1]' <<<"${commands_json}")"
  if [[ -z "${desktop_exec_name}" ]]; then
    desktop_exec_name="${desktop_base%.desktop}"
  fi
  desktop_exec_target="/Programs/${native_name}/current/Commands/${desktop_exec_name}"
  sed -E \
    -e "s#^(TryExec=)([^[:space:]/]+).*#\\1${desktop_exec_target}#" \
    -e "s#^(Exec=)([^[:space:]/]+)(.*)#\\1${desktop_exec_target}\\3#" \
    "${program_root}/RootFS/${rel_desktop}" >"${desktop_target}"
  if [[ "${AUZIX_PUBLISH_UNVALIDATED_DESKTOP_ENTRIES:-0}" != "1" ]]; then
    if grep -q '^NoDisplay=' "${desktop_target}"; then
      sed -i -E 's/^NoDisplay=.*/NoDisplay=true/' "${desktop_target}"
    else
      printf 'NoDisplay=true\n' >>"${desktop_target}"
    fi
    if grep -q '^X-AUZiX-Launcher-State=' "${desktop_target}"; then
      sed -i -E 's/^X-AUZiX-Launcher-State=.*/X-AUZiX-Launcher-State=quarantined-unvalidated/' "${desktop_target}"
    else
      printf 'X-AUZiX-Launcher-State=quarantined-unvalidated\n' >>"${desktop_target}"
    fi
  fi
  chmod 0644 "${desktop_target}"
  compatibility_exports_json="$(
    jq -cn --argjson current "${compatibility_exports_json}" \
      --arg desktop "/System/Compatibility/usr/share/applications/auzix-${native_name}-${desktop_base}" \
      '$current + [$desktop]'
  )"
done < <(
  find "${program_root}/RootFS/usr/share/applications" -maxdepth 1 \
    -type f -name '*.desktop' -printf '%P\n' 2>/dev/null |
    sed 's#^#usr/share/applications/#' |
    sort
)
while IFS= read -r rel_service; do
  service_base="$(basename "${rel_service}")"
  command_name_allowed "${service_base}" || continue
  service_target="${AUZIX_ROOT}/System/Compatibility/${rel_service}"
  mkdir -p "$(dirname "${service_target}")"
  sed -E \
    -e 's#(^Exec=)/usr/bin/([^[:space:]]+)#\1/System/Compatibility/bin/\2#' \
    -e 's#(^Exec=)/usr/sbin/([^[:space:]]+)#\1/System/Compatibility/sbin/\2#' \
    -e 's#(^Exec=)/bin/([^[:space:]]+)#\1/System/Compatibility/bin/\2#' \
    -e 's#(^Exec=)/sbin/([^[:space:]]+)#\1/System/Compatibility/sbin/\2#' \
    -e 's#([[:space:]])/usr/bin/([^[:space:]]+)#\1/System/Compatibility/bin/\2#g' \
    -e 's#([[:space:]])/usr/sbin/([^[:space:]]+)#\1/System/Compatibility/sbin/\2#g' \
    -e 's#([[:space:]])/bin/([^[:space:]]+)#\1/System/Compatibility/bin/\2#g' \
    -e 's#([[:space:]])/sbin/([^[:space:]]+)#\1/System/Compatibility/sbin/\2#g' \
    "${program_root}/RootFS/${rel_service}" >"${service_target}"
  chmod 0644 "${service_target}"
  compatibility_exports_json="$(
    jq -cn --argjson current "${compatibility_exports_json}" \
      --arg service "/System/Compatibility/${rel_service}" \
      '$current + [$service]'
  )"
done < <(
  {
    find "${program_root}/RootFS/usr/share/dbus-1/services" -maxdepth 1 \
      -type f -name '*.service' -printf '%P\n' 2>/dev/null |
      sed 's#^#usr/share/dbus-1/services/#'
    find "${program_root}/RootFS/usr/lib/systemd/system" -maxdepth 1 \
      -type f -name '*.service' -printf '%P\n' 2>/dev/null |
      sed 's#^#usr/lib/systemd/system/#'
    find "${program_root}/RootFS/usr/lib/systemd/user" -maxdepth 1 \
      -type f -name '*.service' -printf '%P\n' 2>/dev/null |
      sed 's#^#usr/lib/systemd/user/#'
  } | sort
)
while IFS= read -r rel_surface; do
  [[ -n "${rel_surface}" ]] || continue
  surface_target="${AUZIX_ROOT}/System/Compatibility/${rel_surface}"
  mkdir -p "$(dirname "${surface_target}")"
  rsync -a "${program_root}/RootFS/${rel_surface}" "${surface_target}"
  compatibility_exports_json="$(
    jq -cn --argjson current "${compatibility_exports_json}" \
      --arg surface "/System/Compatibility/${rel_surface}" \
      '$current + [$surface]'
  )"
done < <(
  {
    find "${program_root}/RootFS/usr/share/dbus-1/system-services" -maxdepth 1 \
      -type f -name '*.service' -printf '%P\n' 2>/dev/null |
      sed 's#^#usr/share/dbus-1/system-services/#'
    find "${program_root}/RootFS/usr/share/dbus-1/system.d" -maxdepth 1 \
      -type f -printf '%P\n' 2>/dev/null |
      sed 's#^#usr/share/dbus-1/system.d/#'
    find "${program_root}/RootFS/usr/share/glib-2.0/schemas" -maxdepth 1 \
      -type f -name '*.xml' -printf '%P\n' 2>/dev/null |
      sed 's#^#usr/share/glib-2.0/schemas/#'
    find "${program_root}/RootFS/usr/libexec" -maxdepth 1 \
      -type f -perm /111 -printf '%P\n' 2>/dev/null |
      sed 's#^#usr/libexec/#'
  } | sort
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

manifest_json_dir="$(mktemp -d)"
trap 'rm -rf "${manifest_json_dir}"' EXIT
printf '%s\n' "${native_depends_json}" >"${manifest_json_dir}/depends.json"
printf '%s\n' "${native_recommends_json}" >"${manifest_json_dir}/recommends.json"
printf '%s\n' "${commands_json}" >"${manifest_json_dir}/commands.json"
printf '%s\n' "${compatibility_exports_json}" >"${manifest_json_dir}/compatibility_exports.json"
printf '%s\n' "${maintainer_surfaces_json}" >"${manifest_json_dir}/maintainer_surfaces.json"
printf '%s\n' "${debian_payload_manifest_json}" >"${manifest_json_dir}/debian_payload_manifest.json"
printf '%s\n' "${debian_md5sums_json}" >"${manifest_json_dir}/debian_md5sums.json"
printf '%s\n' "${validation_library_paths_json}" >"${manifest_json_dir}/validation_library_paths.json"

jq -n \
  --arg name "${native_name}" \
  --arg version "${safe_version}" \
  --arg kind "${package_kind}" \
  --arg source_package "${package_name}" \
  --arg source_version "${package_version}" \
  --arg source_architecture "${package_arch}" \
  --arg source_suite "trixie" \
  --arg upstream_depends "${package_depends}" \
  --arg upstream_recommends "${package_recommends}" \
  --arg description "${package_description}" \
  --arg prefix "/Programs/${native_name}/${safe_version}" \
  --arg current "/Programs/${native_name}/current" \
  --arg repack_class "${repack_class}" \
  --slurpfile depends "${manifest_json_dir}/depends.json" \
  --slurpfile recommends "${manifest_json_dir}/recommends.json" \
  --slurpfile commands "${manifest_json_dir}/commands.json" \
  --slurpfile compatibility_exports "${manifest_json_dir}/compatibility_exports.json" \
  --slurpfile maintainer_surfaces "${manifest_json_dir}/maintainer_surfaces.json" \
  --slurpfile debian_payload_manifest "${manifest_json_dir}/debian_payload_manifest.json" \
  --slurpfile debian_md5sums "${manifest_json_dir}/debian_md5sums.json" \
  --argjson payload_file_count "${payload_file_count}" \
  --argjson payload_size_bytes "${payload_size_bytes}" \
  --slurpfile validation_library_paths "${manifest_json_dir}/validation_library_paths.json" \
  '{
    name: $name,
    version: $version,
    kind: $kind,
    migration_stage: "stage-1-auzix-native-repack",
    prefix: $prefix,
    paths: {prefix: $prefix, current: $current},
    depends: $depends[0],
    recommends: $recommends[0],
    commands: $commands[0],
    compatibility_exports: $compatibility_exports[0],
    runtime_ladder: {
      local_rootfs: true,
      dependency_packages: $depends[0],
      system_surfaces: ["/System/Libraries", "/System/Compatibility", "/System/Settings"]
    },
    maintainer_surfaces: $maintainer_surfaces[0],
    debian_package_db: {
      list_file: ($prefix + "/Metadata/debian-payload.list"),
      md5sums_file: ($prefix + "/Metadata/debian-payload.md5sums"),
      payload_manifest: $debian_payload_manifest[0],
      md5sums: $debian_md5sums[0]
    },
    validation: {
      loader: "/Programs/Libc6/current/RootFS/usr/lib64/ld-linux-x86-64.so.2",
      loader_candidates: [
        "/Programs/Libc6/current/RootFS/usr/lib64/ld-linux-x86-64.so.2",
        "/Programs/Libc6/current/RootFS/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2",
        "/Programs/Libc6/current/RootFS/lib64/ld-linux-x86-64.so.2",
        "/Programs/Libc6/current/RootFS/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
      ],
      library_paths: $validation_library_paths[0]
    },
    description: $description,
    source: {
      type: "debian-binary-package",
      distribution: "debian",
      suite: $source_suite,
      package: $source_package,
      version: $source_version,
      architecture: $source_architecture,
      control_file: ($prefix + "/Metadata/debian-control.txt"),
      control_dir: ($prefix + "/Metadata/debian-control-dir"),
      payload_list: ($prefix + "/Metadata/debian-payload.list"),
      payload_md5sums: ($prefix + "/Metadata/debian-payload.md5sums"),
      upstream_depends: $upstream_depends,
      upstream_recommends: $upstream_recommends,
      upstream_depends_native: $depends[0],
      upstream_recommends_native: $recommends[0],
      payload_file_count: $payload_file_count,
      payload_size_bytes: $payload_size_bytes,
      repack_class: $repack_class
    },
    notes: "Experimental Trixie intake package. Debian payloads are staged under RootFS; detected executable payloads are exposed through AUZiX command wrappers. Packages without commands remain staging metadata until promoted."
  }' >"${receipt_path}"

log "built ${native_name} ${package_version} from ${package_name} (${repack_class}, ${payload_file_count} files, ${command_count} commands)"
