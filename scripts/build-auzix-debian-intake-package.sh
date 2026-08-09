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
        clean="$(sed -E 's/[[:space:]]*\([^)]*\)//g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/:[A-Za-z0-9_-]+$//' <<<"${clean}")"
        [[ "${clean}" =~ ^[a-z0-9][a-z0-9+_.-]*$ ]] || continue
        native="$(auzix_native_name "${clean}")"
        [[ -n "${native}" ]] || continue
        printf '%s\n' "${native}"
      done | awk '!seen[$0]++'
  } | jq -R -s 'split("\n") | map(select(length > 0))'
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
package_recommends="$(dpkg-deb -f "${deb_path}" Recommends 2>/dev/null || true)"
native_depends_json="$(debian_depends_to_native_json "${package_depends}")"
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
state="/System/State/libreoffice"
settings="/System/Settings/libreoffice"
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
  runtime_lib_path="\${runtime_lib_path}:\${runtime_root}/usr/lib/x86_64-linux-gnu:\${runtime_root}/usr/lib:\${runtime_root}/lib/x86_64-linux-gnu:\${runtime_root}/lib"
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
  "\${BB}" mkdir -p /System/Settings/fonts /System/Cache/fontconfig
  {
    echo '<?xml version="1.0"?>'
    echo '<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">'
    echo '<fontconfig>'
    for font_dir in \${font_dirs}; do
      echo "  <dir>\${font_dir}</dir>"
    done
    echo '  <cachedir>/System/Cache/fontconfig</cachedir>'
    echo '</fontconfig>'
  } >/System/Settings/fonts/fonts.conf
  export FONTCONFIG_FILE="/System/Settings/fonts/fonts.conf"
  export FONTCONFIG_PATH="/System/Settings/fonts"
fi
export PATH="\${prefix}/Commands:\${rootfs}/usr/bin:\${common}/usr/bin:\${rootfs}/usr/sbin:\${rootfs}/bin:\${rootfs}/sbin:/Programs/BusyBox/current/Commands:/System/Compatibility/bin:/System/Compatibility/usr/bin\${PATH:+:\${PATH}}"
export XDG_DATA_DIRS="\${rootfs}/usr/share:\${common}/usr/share:/System/Compatibility/usr/share\${XDG_DATA_DIRS:+:\${XDG_DATA_DIRS}}"
export URE_BOOTSTRAP="vnd.sun.star.pathname:\${program}/fundamentalrc"
export UNO_PATH="\${program}"
export LD_LIBRARY_PATH="\${program}:\${rootfs}/usr/lib/x86_64-linux-gnu:\${common}/usr/lib/x86_64-linux-gnu:\${core}/usr/lib/x86_64-linux-gnu:\${rootfs}/usr/lib:\${common}/usr/lib:\${core}/usr/lib\${runtime_lib_path}:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64:/System/Libraries\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
exec "\${program}/soffice" ${libreoffice_mode} "\$@"
EOF
  else
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
for runtime_package in \${runtime_packages}; do
  runtime_root="/Programs/\${runtime_package}/current/RootFS"
  [ -d "\${runtime_root}" ] || continue
  runtime_bin_path="\${runtime_bin_path}:\${runtime_root}/usr/bin:\${runtime_root}/usr/sbin:\${runtime_root}/bin:\${runtime_root}/sbin"
  runtime_data_path="\${runtime_data_path}:\${runtime_root}/usr/share"
  runtime_schema_path="\${runtime_schema_path}:\${runtime_root}/usr/share/glib-2.0/schemas"
  runtime_gi_path="\${runtime_gi_path}:\${runtime_root}/usr/lib/x86_64-linux-gnu/girepository-1.0:\${runtime_root}/usr/lib/girepository-1.0"
  runtime_lib_path="\${runtime_lib_path}:\${runtime_root}/usr/lib/x86_64-linux-gnu:\${runtime_root}/usr/lib:\${runtime_root}/lib/x86_64-linux-gnu:\${runtime_root}/lib"
  if [ -z "\${runtime_loader}" ] && [ -x "\${runtime_root}/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2" ]; then
    runtime_loader="\${runtime_root}/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
  fi
done
export PATH="\${prefix}/Commands:\${rootfs}/usr/bin:\${rootfs}/usr/sbin:\${rootfs}/bin:\${rootfs}/sbin\${runtime_bin_path}:/Programs/BusyBox/current/Commands:/System/Compatibility/bin:/System/Compatibility/usr/bin\${PATH:+:\${PATH}}"
export XDG_DATA_DIRS="\${rootfs}/usr/share\${runtime_data_path}:/System/Compatibility/usr/share\${XDG_DATA_DIRS:+:\${XDG_DATA_DIRS}}"
export GSETTINGS_SCHEMA_DIR="\${rootfs}/usr/share/glib-2.0/schemas\${runtime_schema_path}\${GSETTINGS_SCHEMA_DIR:+:\${GSETTINGS_SCHEMA_DIR}}"
export GI_TYPELIB_PATH="\${rootfs}/usr/lib/x86_64-linux-gnu/girepository-1.0:\${rootfs}/usr/lib/girepository-1.0\${runtime_gi_path}\${GI_TYPELIB_PATH:+:\${GI_TYPELIB_PATH}}"
export LD_LIBRARY_PATH="\${rootfs}/usr/lib/x86_64-linux-gnu:\${rootfs}/usr/lib:\${rootfs}/lib/x86_64-linux-gnu:\${rootfs}/lib\${runtime_lib_path}:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64:/System/Libraries\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
if [ -n "\${runtime_loader}" ]; then
  exec "\${runtime_loader}" --library-path "\${LD_LIBRARY_PATH}" "\${rootfs}/${rel_command}" "\$@"
fi
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
  --arg upstream_recommends "${package_recommends}" \
  --arg description "${package_description}" \
  --arg prefix "/Programs/${native_name}/${safe_version}" \
  --arg current "/Programs/${native_name}/current" \
  --arg repack_class "${repack_class}" \
  --argjson depends "${native_depends_json}" \
  --argjson recommends "${native_recommends_json}" \
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
    recommends: $recommends,
    commands: $commands,
    compatibility_exports: $compatibility_exports,
    runtime_ladder: {
      local_rootfs: true,
      dependency_packages: $depends,
      system_surfaces: ["/System/Libraries", "/System/Compatibility", "/System/Settings"]
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
      upstream_depends: $upstream_depends,
      upstream_recommends: $upstream_recommends,
      upstream_depends_native: $depends,
      upstream_recommends_native: $recommends,
      payload_file_count: $payload_file_count,
      payload_size_bytes: $payload_size_bytes,
      repack_class: $repack_class
    },
    notes: "Experimental Trixie intake package. Debian payloads are staged under RootFS; detected executable payloads are exposed through AUZiX command wrappers. Packages without commands remain staging metadata until promoted."
  }' >"${receipt_path}"

log "built ${native_name} ${package_version} from ${package_name} (${repack_class}, ${payload_file_count} files, ${command_count} commands)"
