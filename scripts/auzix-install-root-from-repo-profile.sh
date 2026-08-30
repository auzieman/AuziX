#!/System/Compatibility/bin/sh
set -eu

# Build an installed AUZiX root from repository package artifacts and package
# profile tiers.  This is live-installer runtime code: no compilers, no local
# source builds, no live-root copy fallback.

usage() {
  cat <<'USAGE'
Usage:
  auzix-install-root-from-repo-profile.sh [--force] [--repo URL] [--profile FILE] /dev/DISK

The disk is destructive when --force is present.  Packages are installed from
repo index metadata into /Work/InstallTarget, with dependencies installed first.
USAGE
}

force=0
repo_url="${AUZIX_REPO_URL:-http://192.168.1.10/auzix/repo}"
profile="${AUZIX_INSTALL_PROFILE:-/System/Settings/install/auzix-vmid135-clean-workstation.packages}"
target=""
link_mode="${AUZIX_LINK_MODE:-strict}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    --repo) repo_url="${2:-}"; shift 2 ;;
    --repo=*) repo_url="${1#--repo=}"; shift ;;
    --profile) profile="${2:-}"; shift 2 ;;
    --profile=*) profile="${1#--profile=}"; shift ;;
    --links) link_mode="${2:-strict}"; shift 2 ;;
    --links=*) link_mode="${1#--links=}"; shift ;;
    --bootloader) shift 2 ;;
    --bootloader=*) shift ;;
    http://*|https://*) repo_url="$1"; shift ;;
    /dev/*) target="$1"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) shift ;;
  esac
done

[ -n "${target}" ] || target=/dev/sda
[ "${force}" = 1 ] || {
  echo "Refusing destructive install without --force" >&2
  usage >&2
  exit 2
}

PATH=/System/Compatibility/bin:/System/Compatibility/sbin:/System/Compatibility/usr/bin:/System/Compatibility/usr/sbin:/Programs/BusyBox/current/Commands:/Programs/BusyBox/1.36.1/Commands:/Programs/AuzixPackageTools/current/Commands:/Programs/Parted/current/Commands:/Programs/E2fsprogs/current/Commands:/Programs/GRUB/current/Commands:/Programs/Curl/current/Commands:/Programs/IPUtils/current/Commands:/Programs/OpenSSH/current/Commands
export PATH

BB=/Programs/BusyBox/current/Commands/busybox
[ -x "${BB}" ] || BB=/Programs/BusyBox/1.36.1/Commands/busybox
JQ="${AUZIX_INSTALL_JQ:-/Programs/AuzixPackageTools/current/Commands/jq}"
PKG_INSTALL=/System/Tools/auzix-install-package
install_plan="${AUZIX_INSTALL_PLAN:-}"
target_root=/Work/InstallTarget
log=/System/Logs/installer/package-built-install.log
index=/System/State/packages/package-built-index.json
work=/run/package-built-install
installed_state=/System/State/packages/package-built-installed.names
missing_state=/System/State/packages/package-built-missing.names
visiting_state=/System/State/packages/package-built-visiting.names
target_package_state="${target_root}/System/State/packages/installed.json"

"${BB}" mkdir -p /System/Logs/installer /System/State/packages "${work}"
: >"${log}"
: >"${installed_state}"
: >"${missing_state}"
: >"${visiting_state}"

log_msg() { echo "$*" | "${BB}" tee -a "${log}"; }
fail() { log_msg "FATAL $*"; exit 1; }
INSTALL_TOTAL_STAGES=11
install_stage() {
  step="$1"
  total="$2"
  shift 2
  log_msg "INSTALL_STAGE step=${step} total=${total} label=$*"
}
find_cmd() {
  for cmd in "$@"; do
    [ -x "${cmd}" ] && { echo "${cmd}"; return 0; }
    command -v "${cmd}" >/dev/null 2>&1 && { command -v "${cmd}"; return 0; }
  done
  return 1
}
part_path() {
  case "${target}" in *nvme*|*mmcblk*|*loop*) echo "${target}p$1";; *) echo "${target}$1";; esac
}
in_file() {
  needle="$1"; file="$2"
  "${BB}" grep -Fxq "${needle}" "${file}" 2>/dev/null
}
append_unique() {
  needle="$1"; file="$2"
  in_file "${needle}" "${file}" || echo "${needle}" >>"${file}"
}
ensure_target_package_state() {
  "${BB}" mkdir -p "${target_root}/System/State/packages"
  if [ ! -s "${target_package_state}" ]; then
    cat >"${target_package_state}" <<'JSON'
{"format":"auzix-installed-v1","installed":[]}
JSON
  fi
}
target_state_installed() {
  name="$1"
  [ -s "${target_package_state}" ] || return 1
  "${JQ}" -e --arg name "${name}" '
    any(.installed[]?; (.name | ascii_downcase) == ($name | ascii_downcase))
  ' "${target_package_state}" >/dev/null 2>&1
}
sync_installed_state_from_target() {
  ensure_target_package_state
  "${JQ}" -r '.installed[]?.name // empty' "${target_package_state}" 2>/dev/null |
    while IFS= read -r installed_name; do
      [ -n "${installed_name}" ] && append_unique "${installed_name}" "${installed_state}"
    done
}
target_receipt_present() {
  name="$1"
  for receipt in "${target_root}/System/PackageDB/${name}-"*.auzix.json "${target_root}/System/PackageDB/${name}.auzix.json"; do
    [ -s "${receipt}" ] && return 0
  done
  return 1
}
target_program_present() {
  name="$1"
  [ -e "${target_root}/Programs/${name}/current" ] || [ -d "${target_root}/Programs/${name}" ]
}
target_base_runtime_provides() {
  name="$1"
  case "${name}" in
    Libc6|LibgccS1|GCC14Base)
      [ -x "${target_root}/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2" ] &&
      [ -x "${target_root}/System/Libraries/Runtime/glibc/libc.so.6" ]
      ;;
    *) return 1 ;;
  esac
}
core_runtime_package() {
  name="$1"
  case "${name}" in
    Libc6|LibgccS1|GCC14Base) return 0 ;;
    *) return 1 ;;
  esac
}
record_target_runtime_substrate() {
  base_name="$1"
  case "${base_name}" in
    Libc6) record_name=ActiveBaseRuntimeLibc6 ;;
    LibgccS1) record_name=ActiveBaseRuntimeLibgcc ;;
    GCC14Base) record_name=ActiveBaseRuntimeGCC ;;
    *) return 0 ;;
  esac
  if target_base_runtime_provides "${base_name}"; then
    append_unique "${record_name}" "${installed_state}"
  fi
  return 0
}
target_core_runtime_dependency_satisfied() {
  name="$1"
  core_runtime_package "${name}" || return 1
  target_base_runtime_provides "${name}" || return 1
  record_target_runtime_substrate "${name}"
  return 0
}
dependency_satisfied() {
  name="$1"
  sync_installed_state_from_target
  target_core_runtime_dependency_satisfied "${name}" ||
  in_file "${name}" "${installed_state}" ||
  target_state_installed "${name}" ||
  target_receipt_present "${name}" ||
  target_program_present "${name}"
}
seed_target_provided_state() {
  ensure_target_package_state
  sync_installed_state_from_target
  if [ -d "${target_root}/System/PackageDB" ]; then
    for receipt in "${target_root}"/System/PackageDB/*.auzix.json "${target_root}"/System/PackageDB/*.json; do
      [ -s "${receipt}" ] || continue
      receipt_name="$("${JQ}" -r '.name // empty' "${receipt}" 2>/dev/null || true)"
      [ -n "${receipt_name}" ] && [ "${receipt_name}" != null ] && append_unique "${receipt_name}" "${installed_state}"
    done
  fi
  if [ -d "${target_root}/Programs" ]; then
    for program_dir in "${target_root}"/Programs/*; do
      [ -d "${program_dir}" ] || continue
      append_unique "${program_dir##*/}" "${installed_state}"
    done
  fi
  for base_name in Libc6 LibgccS1 GCC14Base; do
    record_target_runtime_substrate "${base_name}"
  done
}
link_compat() {
  link_path="$1"; link_target="$2"
  case "${link_mode}" in
    full|compat|legacy) ;;
    *)
      echo "strict alias mode: skipping persistent ${link_path} -> ${link_target}" >>"${log}" 2>/dev/null || true
      return 0
      ;;
  esac
  if [ -L "${target_root}${link_path}" ]; then
    current_target="$(readlink "${target_root}${link_path}" 2>/dev/null || true)"
    if [ "${current_target}" = "${link_target}" ]; then
      return 0
    fi
    echo "alias conflict: ${link_path} -> ${current_target}; wanted ${link_target}; leaving existing link" >>"${log}" 2>/dev/null || true
    return 0
  fi
  [ -e "${target_root}${link_path}" ] && return 0
  ln -s "${link_target}" "${target_root}${link_path}"
}
copy_tree_if_present() {
  source_path="$1"
  target_path="$2"
  [ -e "${source_path}" ] || return 0
  "${BB}" mkdir -p "${target_path}"
  cp -a "${source_path}/." "${target_path}/"
}
sync_live_runtime_contract() {
  # The package profile creates the installed root, while the live ISO root is
  # the proven boot/runtime contract.  Keep disk installs on the same contract:
  # service run scripts, SSH daemon config, and host key state must be present
  # before the first disk boot or the machine comes up stranded.
  copy_tree_if_present /Services "${target_root}/Services"
  copy_tree_if_present /System/Libraries/Runtime/glibc "${target_root}/System/Libraries/Runtime/glibc"
  copy_tree_if_present /System/Settings/ssh "${target_root}/System/Settings/ssh"
  copy_tree_if_present /System/State/ssh "${target_root}/System/State/ssh"

  if [ -d "${target_root}/Services" ]; then
    find "${target_root}/Services" -type f -name run -exec chmod 0755 {} \; 2>/dev/null || true
  fi
  if [ -d "${target_root}/System/State/ssh" ]; then
    chown -R 0:0 "${target_root}/System/State/ssh" 2>/dev/null || true
    chmod 0700 "${target_root}/System/State/ssh" 2>/dev/null || true
    chmod 0600 "${target_root}"/System/State/ssh/ssh_host_*_key 2>/dev/null || true
    chmod 0644 "${target_root}"/System/State/ssh/ssh_host_*_key.pub 2>/dev/null || true
  fi
}
scaffold_minimal_root() {
  "${BB}" mkdir -p \
    "${target_root}/System/Boot" \
    "${target_root}/System/Kernel" \
    "${target_root}/System/Drivers" \
    "${target_root}/System/Settings" \
    "${target_root}/System/State" \
    "${target_root}/System/State/cache" \
    "${target_root}/System/State/lib" \
    "${target_root}/System/State/log" \
    "${target_root}/System/Logs" \
    "${target_root}/System/Libraries/Core" \
    "${target_root}/System/Libraries/Runtime" \
    "${target_root}/System/Libraries/Drivers" \
    "${target_root}/System/Libraries/Compatibility" \
    "${target_root}/System/Tools" \
    "${target_root}/System/Compatibility/bin" \
    "${target_root}/System/Compatibility/sbin" \
    "${target_root}/System/Compatibility/lib" \
    "${target_root}/System/Compatibility/lib64" \
    "${target_root}/System/Compatibility/usr/bin" \
    "${target_root}/System/Compatibility/usr/sbin" \
    "${target_root}/System/Compatibility/usr/lib" \
    "${target_root}/System/Compatibility/usr/local" \
    "${target_root}/System/PackageDB" \
    "${target_root}/System/BuildTools" \
    "${target_root}/Programs" \
    "${target_root}/Services" \
    "${target_root}/Stacks" \
    "${target_root}/Work/Builds" \
    "${target_root}/Work/Sources" \
    "${target_root}/Work/Temp" \
    "${target_root}/Work/Cache" \
    "${target_root}/Work/Containers" \
    "${target_root}/Work/Pipelines" \
    "${target_root}/Users" \
    "${target_root}/Users/auzix/.cache" \
    "${target_root}/Users/auzix/.config" \
    "${target_root}/Users/auzix/.e/e" \
    "${target_root}/Users/auzix/.elementary/config/standard" \
    "${target_root}/Users/auzix/.local/share" \
    "${target_root}/Users/auzix/.midori" \
    "${target_root}/Users/root" \
    "${target_root}/Volumes" \
    "${target_root}/Network/Hosts" \
    "${target_root}/Network/Interfaces" \
    "${target_root}/Network/Routes" \
    "${target_root}/Network/DNS" \
    "${target_root}/dev" \
    "${target_root}/proc" \
    "${target_root}/sys" \
    "${target_root}/run"
  link_compat /bin /System/Compatibility/bin
  link_compat /sbin /System/Compatibility/sbin
  link_compat /lib /System/Compatibility/lib
  link_compat /lib64 /System/Compatibility/lib64
  link_compat /usr /System/Compatibility/usr
  link_compat /etc /System/Settings
  link_compat /var /System/State
  link_compat /tmp /Work/Temp
  link_compat /opt /Programs
  link_compat /home /Users
  link_compat /root /Users/root
  ln -sfn /Work/Temp "${target_root}/System/State/tmp"
  ln -sfn /run "${target_root}/System/State/run"
  ln -sfn /run/lock "${target_root}/System/State/lock"
  cat >"${target_root}/System/Settings/passwd" <<'EOF_PASSWD'
root:x:0:0:root:/Users/root:/System/Compatibility/bin/sh
auzix:x:1000:1000:Auzix User:/Users/auzix:/System/Compatibility/bin/sh
sshd:x:74:74:sshd privilege separation:/run/sshd:/System/Compatibility/bin/false
messagebus:x:101:101:DBus message bus:/run/dbus:/System/Compatibility/bin/false
lightdm:x:102:102:LightDM display manager:/System/State/lightdm:/System/Compatibility/bin/false
EOF_PASSWD
  cat >"${target_root}/System/Settings/group" <<'EOF_GROUP'
root:x:0:
tty:x:5:root,auzix,lightdm
auzix:x:1000:
sshd:x:74:
messagebus:x:101:
lightdm:x:102:
sudo:x:27:auzix
wheel:x:10:root,auzix
input:x:104:root,auzix
video:x:39:root,auzix
render:x:105:root,auzix
audio:x:63:root,auzix
EOF_GROUP
  cat >"${target_root}/System/Settings/shadow" <<'EOF_SHADOW'
root:*:19700:0:99999:7:::
auzix:*:19700:0:99999:7:::
sshd:*:19700:0:99999:7:::
messagebus:*:19700:0:99999:7:::
lightdm:*:19700:0:99999:7:::
EOF_SHADOW
  cat >"${target_root}/System/Settings/shells" <<'EOF_SHELLS'
/System/Compatibility/bin/sh
/System/Compatibility/bin/bash
EOF_SHELLS
  cat >"${target_root}/System/Settings/nsswitch.conf" <<'EOF_NSS'
passwd: files
group: files
shadow: files
hosts: files dns
networks: files
protocols: files
services: files
ethers: files
rpc: files
EOF_NSS
  cat >"${target_root}/System/Settings/hosts" <<'EOF_HOSTS'
127.0.0.1 localhost auzix auzix-live
::1 localhost ip6-localhost ip6-loopback
EOF_HOSTS
  chmod 0600 "${target_root}/System/Settings/shadow" 2>/dev/null || true
  chmod 0755 "${target_root}/Users" "${target_root}/Users/root" "${target_root}/Users/auzix" 2>/dev/null || true
  chown -R 1000:1000 "${target_root}/Users/auzix" 2>/dev/null || true
  cat >"${target_root}/System/PackageDB/root-layout.auzix.json" <<'EOF_ROOT_LAYOUT'
{
  "name": "AuzixRoot",
  "version": "0.1",
  "contract": "strict-root-prototype",
  "compatibility_is_scaffolding": true
}
EOF_ROOT_LAYOUT
}
canonical_name() {
  case "$1" in
    CACerts) echo CaCertificates ;;
    DBUSX11|DBusX11|DBusX11Session) echo DBusUserSession ;;
    Iproute2) echo IPUtils ;;
    OpenSSL) echo Openssl ;;
    *) echo "$1" ;;
  esac
}
pkg_json() {
  name="$1"
  "${JQ}" -c --arg name "${name}" '
    [ .packages[] | select(.name == $name) ]
    | sort_by(.version | tostring)
    | last // empty
  ' "${index}"
}
pkg_field() {
  name="$1"; field="$2"
  pkg_json "${name}" | "${JQ}" -r ".${field} // empty"
}
install_one() {
  raw="$1"
  name="$(canonical_name "${raw}")"
  [ -n "${name}" ] || return 0
  sync_installed_state_from_target
  dependency_satisfied "${name}" && {
    log_msg "SATISFIED package=${name}"
    append_unique "${name}" "${installed_state}"
    return 0
  }
  in_file "${name}" "${visiting_state}" && return 0
  append_unique "${name}" "${visiting_state}"

  json="$(pkg_json "${name}")"
  if [ -z "${json}" ]; then
    log_msg "WARN missing package=${raw} canonical=${name}"
    append_unique "${raw} -> ${name}" "${missing_state}"
    return 0
  fi

  echo "${json}" | "${JQ}" -r '.depends[]?' | while IFS= read -r dep; do
    [ -n "${dep}" ] || continue
    dep_name="$(canonical_name "${dep}")"
    [ "${dep_name}" = "${name}" ] && {
      log_msg "SKIP_SELF_DEP package=${name}"
      continue
    }
    dependency_satisfied "${dep_name}" && {
      log_msg "SATISFIED dependency=${dep_name} for=${name}"
      append_unique "${dep_name}" "${installed_state}"
      continue
    }
    install_one "${dep_name}"
  done
  dependency_satisfied "${name}" && {
    log_msg "SATISFIED package=${name}"
    append_unique "${name}" "${installed_state}"
    return 0
  }
  package="$(echo "${json}" | "${JQ}" -r '.package')"
  sha256="$(echo "${json}" | "${JQ}" -r '.sha256 // empty')"
  [ -n "${package}" ] && [ "${package}" != null ] || fail "package field missing for ${name}"
  out="${work}/${package}.download"
  log_msg "INSTALL package=${name} archive=${package}"
  if ! "${BB}" wget -O "${out}" "${repo_url%/}/packages/${package}"; then
    rm -f "${out}"
    "${BB}" wget -O "${out}" "${repo_url%/}/${package}"
  fi
  if [ -n "${sha256}" ] && [ "${sha256}" != null ]; then
    "${PKG_INSTALL}" --root "${target_root}" --sha256 "${sha256}" "${out}" >>"${log}" 2>&1 ||
      fail "package install failed package=${name} archive=${package}"
  else
    "${PKG_INSTALL}" --root "${target_root}" "${out}" >>"${log}" 2>&1 ||
      fail "package install failed package=${name} archive=${package}"
  fi
  sync_installed_state_from_target
  append_unique "${name}" "${installed_state}"
  log_msg "INSTALLED package=${name} archive=${package}"
}
install_profile() {
  profile_file="$1"
  [ -f "${profile_file}" ] || fail "profile missing: ${profile_file}"
  section=unsectioned
  log_msg "PROFILE_START ${profile_file}"
  while IFS= read -r line || [ -n "${line}" ]; do
    line="${line%%#*}"
    line="$(printf '%s' "${line}" | "${BB}" sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "${line}" ] || continue
    case "${line}" in
      \[*\]) section="${line#[}"; section="${section%]}"; log_msg "TIER ${section}"; continue ;;
    esac
    log_msg "REQUEST tier=${section} package=${line}"
    install_one "${line}"
  done <"${profile_file}"
  log_msg "PROFILE_DONE ${profile_file}"
}
install_named_group() {
  group="$1"
  case "${group}" in
    group-office)
      log_msg "GROUP_START ${group}"
      for pkg in \
        LibreOfficeCommon LibreOfficeCore LibreOfficeWriter LibreOfficeCalc LibreOfficeImpress LibreOfficeDraw \
        AbiWord Gnumeric Pluma Galculator
      do install_one "${pkg}"; done
      log_msg "GROUP_DONE ${group}"
      ;;
    group-dtp)
      log_msg "GROUP_START ${group}"
      for pkg in \
        LibreOfficeDraw LibreOfficeImpress Gnumeric AbiWord Pluma \
        Gimp Inkscape
      do install_one "${pkg}"; done
      log_msg "GROUP_DONE ${group}"
      ;;
    group-internet)
      log_msg "GROUP_START ${group}"
      for pkg in Midori NetSurf Curl CACerts OpenSSL Libnss3 Libnspr4; do install_one "${pkg}"; done
      log_msg "GROUP_DONE ${group}"
      ;;
    group-music-media)
      log_msg "GROUP_START ${group}"
      for pkg in Clementine Audacious MPV VLC FFmpeg GStreamer Ephoto; do install_one "${pkg}"; done
      log_msg "GROUP_DONE ${group}"
      ;;
    group-graphics)
      log_msg "GROUP_START ${group}"
      for pkg in Ephoto Shotwell Gimp Inkscape ImageMagick; do install_one "${pkg}"; done
      log_msg "GROUP_DONE ${group}"
      ;;
    group-dev-ide)
      log_msg "GROUP_START ${group}"
      for pkg in Geany Gedit Pluma Nano Micro Vim Git Binutils Make GCC Clang Cmake Meson NinjaBuild Python3; do install_one "${pkg}"; done
      log_msg "GROUP_DONE ${group}"
      ;;
    group-containers)
      log_msg "GROUP_START ${group}"
      for pkg in ContainersCommon Conmon Crun Netavark AardvarkDNS Podman Buildah Skopeo FuseOverlayfs Slirp4netns Iptables Kmod; do install_one "${pkg}"; done
      log_msg "GROUP_DONE ${group}"
      ;;
    group-retro)
      log_msg "GROUP_START ${group}"
      for pkg in FSUAE FSUAELauncher SDL2 OpenAL; do install_one "${pkg}"; done
      log_msg "GROUP_DONE ${group}"
      ;;
    *)
      log_msg "WARN unknown selected group=${group}"
      append_unique "selected-group:${group}" "${missing_state}"
      ;;
  esac
}
install_plan_groups() {
  [ -n "${install_plan}" ] || return 0
  [ -s "${install_plan}" ] || {
    log_msg "WARN install plan not found or empty: ${install_plan}"
    append_unique "install-plan:${install_plan}" "${missing_state}"
    return 0
  }
  log_msg "PLAN_GROUPS_START ${install_plan}"
  "${JQ}" -r '.packages.selected[]? // empty' "${install_plan}" 2>/dev/null | while IFS= read -r group; do
    [ -n "${group}" ] || continue
    install_named_group "${group}"
  done
  log_msg "PLAN_GROUPS_DONE ${install_plan}"
}

[ -x "${JQ}" ] || fail "jq missing: ${JQ}"
[ -x "${PKG_INSTALL}" ] || fail "target package installer missing: ${PKG_INSTALL}"
[ -b "${target}" ] || fail "target block device missing: ${target}"
PARTED="$(find_cmd /Programs/Parted/current/Commands/parted /System/Compatibility/usr/sbin/parted /System/Compatibility/sbin/parted /System/Compatibility/usr/bin/parted /System/Compatibility/bin/parted parted)" || fail "parted missing"
MKFS="$(find_cmd /Programs/E2fsprogs/current/Commands/mkfs.ext4 /System/Compatibility/sbin/mkfs.ext4 mkfs.ext4)" || fail "mkfs.ext4 missing"

log_msg "PACKAGE_PROFILE_INSTALL_START target=${target} repo=${repo_url} profile=${profile}"
install_stage 1 "${INSTALL_TOTAL_STAGES}" "fetching AUZiX package repository index"
"${BB}" wget -O "${index}.tmp" "${repo_url%/}/index.json"
"${JQ}" -e '.format == "auzix-repo-v1" and (.packages|type == "array")' "${index}.tmp" >/dev/null || fail "repo index invalid"
mv "${index}.tmp" "${index}"
log_msg "repo_packages=$("${JQ}" '.packages|length' "${index}")"

for mp in "${target_root}/dev/pts" "${target_root}/dev/shm" "${target_root}/dev" "${target_root}/proc" "${target_root}/sys" "${target_root}/Home" "${target_root}/Work" "${target_root}"; do
  "${BB}" umount "${mp}" 2>/dev/null || true
done

install_stage 2 "${INSTALL_TOTAL_STAGES}" "partitioning split AUZiX disk layout"
root_part="$(part_path 1)"
home_part="$(part_path 2)"
work_part="$(part_path 3)"
case "${AUZIX_INSTALL_PREPARED_TARGET:-0}" in
  1|yes|true|on)
    log_msg "PREPARED_TARGET storage layout supplied by media wrapper"
    [ -b "${root_part}" ] && [ -b "${home_part}" ] && [ -b "${work_part}" ] ||
      fail "prepared target partition nodes are incomplete"
    install_stage 3 "${INSTALL_TOTAL_STAGES}" "using preformatted AUZiX root, Home, and Work filesystems"
    ;;
  *)
    "${BB}" dd if=/dev/zero of="${target}" bs=1M count=8
    "${PARTED}" -s "${target}" mklabel msdos
    "${PARTED}" -s "${target}" mkpart primary ext4 1MiB 60%
    "${PARTED}" -s "${target}" mkpart primary ext4 60% 80%
    "${PARTED}" -s "${target}" mkpart primary ext4 80% 100%
    "${PARTED}" -s "${target}" set 1 boot on || true
    "${BB}" sleep 1
    install_stage 3 "${INSTALL_TOTAL_STAGES}" "formatting AUZiX root, Home, and Work filesystems"
    "${MKFS}" -F -L AUZIXROOT "${root_part}" >>"${log}" 2>&1
    "${MKFS}" -F -L AUZIXHOME "${home_part}" >>"${log}" 2>&1
    "${MKFS}" -F -L AUZIXWORK "${work_part}" >>"${log}" 2>&1
    ;;
esac
root_uuid="$("${BB}" blkid "${root_part}" 2>/dev/null | "${BB}" sed -n 's/.*UUID="\([^"]*\)".*/\1/p' | "${BB}" head -n 1 || true)"
if [ -n "${root_uuid}" ]; then
  root_boot_spec="UUID=${root_uuid}"
else
  root_boot_spec="${root_part}"
  log_msg "WARN root UUID unavailable for ${root_part}; falling back to device path"
fi

install_stage 4 "${INSTALL_TOTAL_STAGES}" "mounting target filesystems"
"${BB}" mkdir -p "${target_root}"
"${BB}" mount "${root_part}" "${target_root}"
"${BB}" mkdir -p "${target_root}/Home" "${target_root}/Work" "${target_root}/Programs"
"${BB}" mount "${home_part}" "${target_root}/Home"
"${BB}" mount "${work_part}" "${target_root}/Work"

install_stage 5 "${INSTALL_TOTAL_STAGES}" "scaffolding strict AUZiX root contract"
scaffold_minimal_root >>"${log}" 2>&1 || fail "minimal root scaffold failed"
case "${AUZIX_INSTALL_COPY_SEED_RUNTIME:-0}" in
  1|yes|true|on)
    log_msg "COMPAT seed runtime copy enabled"
    sync_live_runtime_contract >>"${log}" 2>&1
    ;;
  *)
    log_msg "PACKAGE_ONLY seed runtime copy disabled; installed packages own runtime and service surfaces"
    ;;
esac
ensure_target_package_state >>"${log}" 2>&1 || fail "target package state initialization failed"
seed_target_provided_state >>"${log}" 2>&1 || fail "bootstrap substrate inventory failed"

install_stage 6 "${INSTALL_TOTAL_STAGES}" "installing base remote profile"
seed_profile=/System/Settings/install/auzix-tiny-netinstall-remote.packages
[ -f "${seed_profile}" ] && install_profile "${seed_profile}"
install_stage 7 "${INSTALL_TOTAL_STAGES}" "installing selected workstation package profile"
install_profile "${profile}"
install_stage 8 "${INSTALL_TOTAL_STAGES}" "installing selected package groups"
install_plan_groups

install_stage 9 "${INSTALL_TOTAL_STAGES}" "finalizing AUZiX runtime contract"
"${BB}" mkdir -p "${target_root}/System/State/install" "${target_root}/boot/grub" "${target_root}/System/Boot"
{
  echo "root_build_mode=package-profile"
  echo "layout=user-work-programs"
  echo "profile=${profile}"
  echo "root=${root_part}"
  echo "root_boot_spec=${root_boot_spec}"
  echo "home=${home_part}"
  echo "work=${work_part}"
} >"${target_root}/System/State/install/storage-layout.txt"
cp "${installed_state}" "${target_root}/System/State/install/package-installed.names"
cp "${missing_state}" "${target_root}/System/State/install/package-missing.names"
find "${target_root}/System/PackageDB" -maxdepth 1 -type f -name '*.json' | sort >"${target_root}/System/State/install/package-receipts.txt" 2>/dev/null || true

live_tools=""
for candidate in \
  /workspace/scripts/add-auzix-live-tools.sh \
  /mnt/ns1/AuziX/src/scripts/add-auzix-live-tools.sh \
  /System/Tools/add-auzix-live-tools.sh \
  ./scripts/add-auzix-live-tools.sh
do
  if [ -x "${candidate}" ]; then
    live_tools="${candidate}"
    break
  fi
done
if [ -z "${live_tools}" ]; then
  fail "add-auzix-live-tools.sh not found; disk install must reuse ISO root-prep contract"
fi
log_msg "ROOT_PREP source=${live_tools} target=${target_root}"
"${live_tools}" "${target_root}" >>"${log}" 2>&1 || fail "root prep failed via ${live_tools}"
log_msg "COMPAT_REPAIR_START name=runtime-and-service-contract source=bootstrap-seed"
sync_live_runtime_contract >>"${log}" 2>&1 || fail "runtime and service compatibility repair failed"
log_msg "COMPAT_REPAIR_DONE name=runtime-and-service-contract source=bootstrap-seed"
[ -x "${target_root}/System/Boot/StartSequence" ] || fail "root prep did not create StartSequence"
[ -x "${target_root}/System/Boot/InstalledInit" ] || fail "root prep did not create InstalledInit"
cp "${target_root}/System/Boot/InstalledInit" "${target_root}/init"
chmod 755 "${target_root}/init"
if [ -s "${target_root}/System/Compatibility/etc/ssl/certs/ca-certificates.crt" ]; then
  mkdir -p "${target_root}/System/Compatibility/usr/lib/ssl"
  ln -sfn /System/Compatibility/etc/ssl/certs/ca-certificates.crt "${target_root}/System/Compatibility/etc/ssl/cert.pem"
  ln -sfn /System/Compatibility/etc/ssl/certs/ca-certificates.crt "${target_root}/System/Compatibility/usr/lib/ssl/cert.pem"
fi

install_stage 10 "${INSTALL_TOTAL_STAGES}" "copying boot payload and installing bootloader"
boot_source=""
for candidate in /run/auzix-iso/boot /run/live/iso/boot /boot; do
  if [ -f "${candidate}/vmlinuz" ] && [ -f "${candidate}/initramfs.cpio.gz" ]; then
    boot_source="${candidate}"
    break
  fi
done
if [ -z "${boot_source}" ]; then
  fail "boot payload not found; expected vmlinuz and initramfs.cpio.gz in mounted live media"
fi
cp -p "${boot_source}/vmlinuz" "${target_root}/boot/vmlinuz"
cp -p "${boot_source}/initramfs.cpio.gz" "${target_root}/boot/initramfs.cpio.gz"
log_msg "BOOT_PAYLOAD source=${boot_source} kernel=/boot/vmlinuz initramfs=/boot/initramfs.cpio.gz"
cat >"${target_root}/boot/grub/grub.cfg" <<EOF_GRUB
set timeout=3
set default=0
menuentry "AUZiX package-profile root" {
    linux /boot/vmlinuz console=ttyS0,115200 console=tty0 root=${root_boot_spec} auzix.root=${root_part} init=/init rw
    initrd /boot/initramfs.cpio.gz
}
EOF_GRUB

mount -t proc proc "${target_root}/proc" 2>/dev/null || true
mount -t sysfs sysfs "${target_root}/sys" 2>/dev/null || true
mount -t devtmpfs devtmpfs "${target_root}/dev" 2>/dev/null || true
if command -v grub-install >/dev/null 2>&1; then
  grub-install --boot-directory="${target_root}/boot" "${target}" >>"${log}" 2>&1 || fail "grub-install failed"
elif [ -x /System/Compatibility/usr/sbin/grub-install ]; then
  /System/Compatibility/usr/sbin/grub-install --boot-directory="${target_root}/boot" "${target}" >>"${log}" 2>&1 || fail "grub-install failed"
fi

log_msg "PACKAGE_PROFILE_INSTALL_DONE root=${root_part} boot_spec=${root_boot_spec} installed=$("${BB}" wc -l <"${installed_state}") missing=$("${BB}" wc -l <"${missing_state}")"
if [ -s "${missing_state}" ]; then
  log_msg "PACKAGE_PROFILE_MISSING_START"
  cat "${missing_state}" | "${BB}" tee -a "${log}" >/dev/null
  log_msg "PACKAGE_PROFILE_MISSING_END"
fi
install_stage 11 "${INSTALL_TOTAL_STAGES}" "syncing and unmounting package-profile install"
sync
for mp in "${target_root}/dev/pts" "${target_root}/dev/shm" "${target_root}/dev" "${target_root}/proc" "${target_root}/sys" "${target_root}/Home" "${target_root}/Work" "${target_root}"; do
  "${BB}" umount "${mp}" 2>/dev/null || "${BB}" umount -l "${mp}" 2>/dev/null || true
done
sync
log_msg "INSTALL_READY_TO_REBOOT"
log_msg "ACTION remove_or_disconnect_live_iso_and_boot_from_disk"
log_msg "INSTALL_DONE root=${root_part} boot_spec=${root_boot_spec} layout=user-work-programs bootloader=grub"
