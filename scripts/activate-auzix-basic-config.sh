#!/System/Compatibility/bin/sh
# Minimal AUZiX package activation pass.
# Applies the Debian-style configuration surfaces already present in installed
# package RootFS trees without rebuilding packages.
set -u

PATH=/System/Compatibility/sbin:/System/Compatibility/bin:/System/Compatibility/usr/sbin:/System/Compatibility/usr/bin:/Programs/BusyBox/current/Commands:/Programs/BusyBox/1.36.1/Commands:/Programs/AuzixPackageTools/current/Commands
export PATH
LD_LIBRARY_PATH=/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/usr/lib:/System/Compatibility/lib:/System/Libraries
export LD_LIBRARY_PATH

BB=${BB:-/Programs/BusyBox/1.36.1/Commands/busybox}
ROOT=${AUZIX_ROOT:-}
[ -n "${ROOT}" ] || ROOT=

p() { printf '%s%s' "${ROOT}" "$1"; }
log_dir="$(p /System/Logs/packages)"
log_file="${log_dir}/activation-basic.log"

"${BB}" mkdir -p \
  "$(p /System/Settings)" \
  "$(p /System/Settings/default)" \
  "$(p /System/State)" \
  "$(p /System/Cache)" \
  "$(p /System/Compatibility)" \
  "$(p /System/Compatibility/etc)" \
  "$(p /System/Compatibility/etc/fonts)" \
  "$(p /System/Compatibility/usr/libexec)" \
  "$(p /System/Compatibility/usr/lib/systemd/system)" \
  "$(p /System/Compatibility/usr/share/dbus-1)" \
  "$(p /System/Compatibility/usr/share/polkit-1)" \
  "$(p /System/Compatibility/usr/share/applications)" \
  "$(p /System/Compatibility/usr/share/icons)" \
  "$(p /System/Compatibility/usr/share/mime)" \
  "$(p /System/Compatibility/usr/share/enlightenment)" \
  "$(p /System/Compatibility/usr/share/enlightenment/themes)" \
  "$(p /System/Compatibility/usr/share/enlightenment/data/themes)" \
  "$(p /System/Compatibility/usr/share/enlightenment/data/backgrounds)" \
  "$(p /System/Compatibility/usr/share/elementary)" \
  "$(p /System/Compatibility/usr/share/efreet)" \
  "$(p /System/Compatibility/usr/share/libinput)" \
  "$(p /System/Compatibility/usr/share/terminology)" \
  "$(p /System/Compatibility/usr/share/locale)" \
  "$(p /System/Compatibility/usr/share/glib-2.0/schemas)" \
  "$(p /System/Compatibility/usr/share/fonts)" \
  "$(p /System/Fonts)" \
  "$(p /var/cache/fontconfig)" \
  "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu)" \
  "$(p /System/Compatibility/lib/x86_64-linux-gnu)" \
  "$(p /System/Compatibility/usr/lib)" \
  "$(p /System/Compatibility/lib)" \
  "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/ecore_evas)" \
  "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/evas)" \
  "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/edje)" \
  "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/ecore_imf)" \
  "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/elementary)" \
  "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment)" \
  "$(p /System/Compatibility/lib/udev/rules.d)" \
  "$(p /System/Compatibility/usr/lib/udev/rules.d)" \
  "$(p /System/Settings/systemd/system)" \
  "$(p /System/Settings/dbus-1/system.d)" \
  "$(p /System/Settings/pam.d)" \
  "$(p /System/Settings/tmpfiles.d)" \
  "$(p /System/Settings/sysusers.d)" \
  "$(p /run)" "$(p /run/dbus)" "$(p /run/lock)" "$(p /run/user)" \
  "$(p /var/lib/dbus)" "$(p /var/lib/lightdm)" "$(p /var/log)" \
  "${log_dir}" 2>/dev/null || true

: >"${log_file}" 2>/dev/null || true
log() { echo "[activation-basic] $*" >>"${log_file}" 2>/dev/null || true; }

ensure_core_aliases() {
  # Keep AUZiX's canonical settings tree and the compatibility tree visible
  # through the same paths Debian postinst snippets and desktop services expect.
  [ -e "$(p /System/Compatibility/etc/xdg)" ] ||
    "${BB}" ln -s /System/Settings/xdg "$(p /System/Compatibility/etc/xdg)" 2>/dev/null || true
}

ensure_locale_defaults() {
  locale_file="$(p /System/Settings/default/locale)"
  if [ ! -s "${locale_file}" ]; then
    "${BB}" mkdir -p "${locale_file%/*}" 2>/dev/null || true
    printf '%s\n' \
      'LANG=en_US.UTF-8' \
      'LANGUAGE=en_US:en' \
      'LC_ALL=en_US.UTF-8' >"${locale_file}" 2>/dev/null || true
    "${BB}" chmod 0644 "${locale_file}" 2>/dev/null || true
  fi
}

link_or_copy() {
  src="$1"
  dst="$2"
  [ -e "${src}" ] || return 0
  "${BB}" mkdir -p "${dst%/*}" 2>/dev/null || true
  "${BB}" rm -f "${dst}" 2>/dev/null || true
  "${BB}" ln -s "${src#${ROOT}}" "${dst}" 2>/dev/null ||
    "${BB}" cp -a "${src}" "${dst}" 2>/dev/null || true
}

copy_tree_files() {
  src_dir="$1"
  dst_dir="$2"
  [ -d "${src_dir}" ] || return 0
  (
    cd "${src_dir}" 2>/dev/null || exit 0
    "${BB}" find . -type f -o -type l 2>/dev/null
  ) | while IFS= read -r rel; do
    rel="${rel#./}"
    [ -n "${rel}" ] || continue
    link_or_copy "${src_dir}/${rel}" "${dst_dir}/${rel}"
  done
}

publish_libexec_wrappers() {
  src_dir="$1"
  dst_dir="$2"
  [ -d "${src_dir}" ] || return 0
  "${BB}" mkdir -p "${dst_dir}" "$(p /System/Compatibility/usr/libexec/auzix-real)" 2>/dev/null || true
  (
    cd "${src_dir}" 2>/dev/null || exit 0
    "${BB}" find . -maxdepth 1 -type f -perm /111 2>/dev/null
  ) | while IFS= read -r rel; do
    rel="${rel#./}"
    [ -n "${rel}" ] || continue
    src="${src_dir}/${rel}"
    wrapper="${dst_dir}/${rel}"
    real="$(p /System/Compatibility/usr/libexec/auzix-real/${rel}.real)"
    "${BB}" rm -f "${real}" 2>/dev/null || true
    "${BB}" ln -s "${src#${ROOT}}" "${real}" 2>/dev/null ||
      "${BB}" cp -a "${src}" "${real}" 2>/dev/null || true
    cat >"${wrapper}" <<EOF 2>/dev/null || true
#!/Programs/BusyBox/current/Commands/busybox sh
set -eu
libs="/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/usr/lib:/System/Compatibility/lib:/System/Compatibility/lib64:/System/Libraries"
for d in /Programs/*/current/RootFS/usr/lib/x86_64-linux-gnu /Programs/*/current/RootFS/lib/x86_64-linux-gnu /Programs/*/current/RootFS/usr/lib /Programs/*/current/RootFS/lib; do
  [ -d "\${d}" ] && libs="\${libs}:\${d}"
done
export LD_LIBRARY_PATH="\${libs}\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
export XDG_DATA_DIRS="/System/Compatibility/usr/share:/usr/share\${XDG_DATA_DIRS:+:\${XDG_DATA_DIRS}}"
exec "${real#${ROOT}}" "\$@"
EOF
    "${BB}" chmod 0755 "${wrapper}" 2>/dev/null || true
  done
}

link_matching_files() {
  src_dir="$1"
  dst_dir="$2"
  pattern="$3"
  [ -d "${src_dir}" ] || return 0
  "${BB}" mkdir -p "${dst_dir}" 2>/dev/null || true
  "${BB}" find "${src_dir}" -type f -name "${pattern}" 2>/dev/null | while IFS= read -r asset; do
    base="${asset##*/}"
    link_or_copy "${asset}" "${dst_dir}/${base}"
  done
}

copy_top_level_files() {
  src_dir="$1"
  dst_dir="$2"
  [ -d "${src_dir}" ] || return 0
  "${BB}" mkdir -p "${dst_dir}" 2>/dev/null || true
  "${BB}" find "${src_dir}" -maxdepth 1 \( -type f -o -type l \) 2>/dev/null | while IFS= read -r asset; do
    base="${asset##*/}"
    link_or_copy "${asset}" "${dst_dir}/${base}"
  done
}

activate_auzix_theme_assets() {
  # AUZiX theme/wallpaper packages keep their canonical payload under
  # /Programs, but Enlightenment discovers .edj themes and backgrounds from
  # its data directories and from a user's E profile. Export both surfaces.
  e_legacy_theme_dir="$(p /System/Compatibility/usr/share/enlightenment/themes)"
  e_theme_dir="$(p /System/Compatibility/usr/share/enlightenment/data/themes)"
  e_bg_dir="$(p /System/Compatibility/usr/share/enlightenment/data/backgrounds)"

  for pkg_root in "$(p /Programs/AuzixThemes)"/* "$(p /Programs/DesktopAssets)"/*; do
    [ -d "${pkg_root}" ] || continue
    link_matching_files "${pkg_root}/Resources/themes" "${e_legacy_theme_dir}" '*.edj'
    link_matching_files "${pkg_root}/Resources/themes" "${e_theme_dir}" '*.edj'
    link_matching_files "${pkg_root}/Resources/display/assets/themes" "${e_legacy_theme_dir}" '*.edj'
    link_matching_files "${pkg_root}/Resources/display/assets/themes" "${e_theme_dir}" '*.edj'
    link_matching_files "${pkg_root}/Resources/backgrounds" "${e_bg_dir}" '*.edj'
    link_matching_files "${pkg_root}/Resources/display/assets/backgrounds" "${e_bg_dir}" '*.edj'
  done

  for user_home in "$(p /Users)"/*; do
    [ -d "${user_home}" ] || continue
    user_theme_dir="${user_home}/.e/e/themes"
    user_bg_dir="${user_home}/.e/e/backgrounds"
    user_elementary_theme_dir="${user_home}/.elementary/themes"
    "${BB}" mkdir -p "${user_theme_dir}" "${user_bg_dir}" "${user_elementary_theme_dir}" 2>/dev/null || true
    copy_tree_files "${e_legacy_theme_dir}" "${user_theme_dir}"
    copy_tree_files "${e_legacy_theme_dir}" "${user_elementary_theme_dir}"
    copy_tree_files "${e_theme_dir}" "${user_theme_dir}"
    copy_tree_files "${e_theme_dir}" "${user_elementary_theme_dir}"
    copy_tree_files "${e_bg_dir}" "${user_bg_dir}"
    owner="${user_home##*/}"
    "${BB}" chown -R "${owner}:${owner}" "${user_home}/.e" "${user_home}/.elementary" 2>/dev/null || true
  done
}

activate_auzix_desktop_profile_assets() {
  # DesktopAssets also carries the known-good E profile used by the graphical
  # live demo. Install it for new/incomplete AUZiX users; allow an explicit
  # refresh when rebuilding a workstation profile.
  profile_src="$(p /Programs/DesktopAssets/auzietek/Resources/display/assets/config)"
  [ -d "${profile_src}" ] || return 0

  for user_home in "$(p /Users)"/*; do
    [ -d "${user_home}" ] || continue
    user_config="${user_home}/.e/e/config"
    if [ -s "${user_config}/standard/e.cfg" ] && [ "${AUZIX_REFRESH_DESKTOP_DEFAULTS:-0}" != "1" ]; then
      continue
    fi
    copy_tree_files "${profile_src}" "${user_config}"
    owner="${user_home##*/}"
    "${BB}" chown -R "${owner}:${owner}" "${user_home}/.e" 2>/dev/null || true
  done
}

ensure_machine_id() {
  mid_file="$(p /System/Settings/machine-id)"
  if [ ! -s "${mid_file}" ] && [ -r /proc/sys/kernel/random/uuid ]; then
    "${BB}" tr -d '-' </proc/sys/kernel/random/uuid >"${mid_file}" 2>/dev/null || true
  fi
  [ -s "${mid_file}" ] || echo 00000000000000000000000000000000 >"${mid_file}" 2>/dev/null || true
  "${BB}" cp -f "${mid_file}" "$(p /var/lib/dbus/machine-id)" 2>/dev/null || true
  "${BB}" chmod 0444 "${mid_file}" 2>/dev/null || true
  "${BB}" chmod 0644 "$(p /var/lib/dbus/machine-id)" 2>/dev/null || true
}

write_file_if_missing_or_empty() {
  dst="$1"
  body="$2"
  if [ ! -s "${dst}" ]; then
    "${BB}" mkdir -p "${dst%/*}" 2>/dev/null || true
    printf '%s\n' "${body}" >"${dst}" 2>/dev/null || true
    "${BB}" chmod 0644 "${dst}" 2>/dev/null || true
  fi
}

ensure_sudo_pam_bootstrap() {
  # Debian-derived sudo still initializes PAM even for NOPASSWD sudoers rules.
  # If package extraction exposes /etc/pam.d/sudo but not the included
  # common-* stack, sudo aborts before it ever reaches sudoers. Keep a tiny
  # permissive bootstrap policy until the full PAM package owns these files.
  pam_dir="$(p /System/Settings/pam.d)"
  "${BB}" mkdir -p "${pam_dir}" \
    "$(p /run/sudo/ts)" \
    "$(p /var/lib/sudo/lectured)" 2>/dev/null || true

  write_file_if_missing_or_empty "${pam_dir}/common-auth" \
"# AUZiX minimal PAM base for bootstrap/workstation validation
auth required pam_permit.so"
  write_file_if_missing_or_empty "${pam_dir}/common-account" \
"# AUZiX minimal PAM base for bootstrap/workstation validation
account required pam_permit.so"
  write_file_if_missing_or_empty "${pam_dir}/common-password" \
"# AUZiX minimal PAM base for bootstrap/workstation validation
password required pam_permit.so"
  write_file_if_missing_or_empty "${pam_dir}/common-session" \
"# AUZiX minimal PAM base for bootstrap/workstation validation
session required pam_permit.so"
  write_file_if_missing_or_empty "${pam_dir}/common-session-noninteractive" \
"# AUZiX minimal PAM base for bootstrap/workstation validation
session required pam_permit.so"

  if [ ! -e "${pam_dir}/sudo" ]; then
    printf '%s\n' \
      '#%PAM-1.0' \
      '@include common-auth' \
      '@include common-account' \
      '@include common-session-noninteractive' >"${pam_dir}/sudo" 2>/dev/null || true
    "${BB}" chmod 0644 "${pam_dir}/sudo" 2>/dev/null || true
  fi
  if [ ! -e "${pam_dir}/sudo-i" ]; then
    link_or_copy "${pam_dir}/sudo" "${pam_dir}/sudo-i"
  fi
  if [ ! -e "${pam_dir}/other" ]; then
    printf '%s\n' \
      '# AUZiX fallback PAM policy during bootstrap' \
      '@include common-auth' \
      '@include common-account' \
      '@include common-password' \
      '@include common-session' >"${pam_dir}/other" 2>/dev/null || true
    "${BB}" chmod 0644 "${pam_dir}/other" 2>/dev/null || true
  fi

  [ -e "$(p /System/Compatibility/lib/security)" ] ||
    "${BB}" ln -s /System/Compatibility/lib/x86_64-linux-gnu/security "$(p /System/Compatibility/lib/security)" 2>/dev/null || true
  [ -e "$(p /etc/pam.d)" ] ||
    "${BB}" ln -s /System/Settings/pam.d "$(p /etc/pam.d)" 2>/dev/null || true
  [ -e "$(p /System/Compatibility/etc/pam.d)" ] ||
    "${BB}" ln -s /System/Settings/pam.d "$(p /System/Compatibility/etc/pam.d)" 2>/dev/null || true

  for sudo_bin in \
    "$(p /Programs/Sudo/current/Commands/sudo)" \
    "$(p /Programs/Sudo/host/Commands/sudo)" \
    "$(p /System/Compatibility/usr/bin/sudo)" \
    "$(p /System/Compatibility/bin/sudo)"; do
    [ -e "${sudo_bin}" ] || continue
    "${BB}" chown root:root "${sudo_bin}" 2>/dev/null || true
    "${BB}" chmod 4755 "${sudo_bin}" 2>/dev/null || true
  done

  "${BB}" chown -R root:root "$(p /run/sudo)" "$(p /var/lib/sudo)" 2>/dev/null || true
  "${BB}" chmod 0711 "$(p /run/sudo)" 2>/dev/null || true
  "${BB}" chmod 0700 "$(p /run/sudo/ts)" "$(p /var/lib/sudo/lectured)" 2>/dev/null || true
}

ensure_interactive_command_surface() {
  # A login shell must land in AUZiX with ordinary operator tools visible.
  # The canonical payload remains under /Programs; these are generated command
  # shims for compatibility and human ergonomics.
  compat_bin="$(p /System/Compatibility/bin)"
  compat_ubin="$(p /System/Compatibility/usr/bin)"
  "${BB}" mkdir -p "${compat_bin}" "${compat_ubin}" "$(p /System/Settings)" 2>/dev/null || true

  busybox_target=/Programs/BusyBox/1.36.1/Commands/busybox
  [ -e "$(p /Programs/BusyBox/current/Commands/busybox)" ] && busybox_target=/Programs/BusyBox/current/Commands/busybox
  for applet in sh ash su cat df du ps grep sed less id whoami env mount umount mkdir ln ls rm cp mv chmod chown; do
    [ -e "${compat_bin}/${applet}" ] || "${BB}" ln -s "${busybox_target}" "${compat_bin}/${applet}" 2>/dev/null || true
  done

  [ -e "${compat_bin}/sudo" ] ||
    "${BB}" ln -s /Programs/Sudo/host/Commands/sudo "${compat_bin}/sudo" 2>/dev/null || true
  [ -e "${compat_bin}/flatpak" ] ||
    "${BB}" ln -s /Programs/Flatpak/current/Commands/flatpak "${compat_bin}/flatpak" 2>/dev/null || true
  [ -e "${compat_bin}/podman" ] ||
    "${BB}" ln -s /Programs/Podman/current/Commands/podman "${compat_bin}/podman" 2>/dev/null || true
  [ -e "${compat_ubin}/flatpak" ] ||
    "${BB}" ln -s /Programs/Flatpak/current/Commands/flatpak "${compat_ubin}/flatpak" 2>/dev/null || true
  [ -e "${compat_ubin}/podman" ] ||
    "${BB}" ln -s /Programs/Podman/current/Commands/podman "${compat_ubin}/podman" 2>/dev/null || true

  for command_dir in "$(p /Programs)"/*/current/Commands; do
    [ -d "${command_dir}" ] || continue
    for command_path in "${command_dir}"/*; do
      [ -f "${command_path}" ] || [ -L "${command_path}" ] || continue
      [ -x "${command_path}" ] || continue
      command_name="${command_path##*/}"
      case "${command_name}" in
        *.before-*|*.real|*.debug|*.bak|*.orig) continue ;;
      esac
      [ -e "${compat_ubin}/${command_name}" ] ||
        "${BB}" ln -s "${command_path#${ROOT}}" "${compat_ubin}/${command_name}" 2>/dev/null || true
    done
  done
  if [ -x "$(p /Programs/L3afpad/current/Commands/l3afpad)" ] && [ ! -e "${compat_ubin}/leafpad" ]; then
    "${BB}" ln -s /Programs/L3afpad/current/Commands/l3afpad "${compat_ubin}/leafpad" 2>/dev/null || true
  fi

  profile="$(p /System/Settings/profile)"
  if [ -L "${profile}" ]; then
    "${BB}" rm -f "${profile}" 2>/dev/null || true
  fi
  if [ ! -s "${profile}" ]; then
    "${BB}" cat >"${profile}" <<'EOF' 2>/dev/null || true
# AUZiX interactive shell defaults
export PATH=/Programs/BusyBox/current/Commands:/Programs/BusyBox/1.36.1/Commands:/System/Compatibility/usr/local/sbin:/System/Compatibility/usr/local/bin:/System/Compatibility/usr/sbin:/System/Compatibility/usr/bin:/System/Compatibility/sbin:/System/Compatibility/bin:/Programs/Podman/current/Commands:/Programs/Flatpak/current/Commands:/Programs/Sudo/current/Commands:/Programs/Sudo/host/Commands:${PATH:-}
export LD_LIBRARY_PATH=/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/usr/lib:/System/Compatibility/lib:/System/Libraries:${LD_LIBRARY_PATH:-}
export XDG_DATA_DIRS=/System/Compatibility/usr/local/share:/System/Compatibility/usr/share:/var/lib/flatpak/exports/share:/Users/${USER:-auzix}/.local/share/flatpak/exports/share:${XDG_DATA_DIRS:-}
export XDG_CONFIG_DIRS=/System/Settings/xdg:/System/Compatibility/etc/xdg:${XDG_CONFIG_DIRS:-}
EOF
    "${BB}" chmod 0644 "${profile}" 2>/dev/null || true
  fi

  for user_home in "$(p /Users)"/*; do
    [ -d "${user_home}" ] || continue
    owner="${user_home##*/}"
    for shell_rc in "${user_home}/.profile" "${user_home}/.shrc"; do
      if [ ! -s "${shell_rc}" ]; then
        printf '%s\n' '[ -r /System/Settings/profile ] && . /System/Settings/profile' >"${shell_rc}" 2>/dev/null || true
        "${BB}" chown "${owner}:${owner}" "${shell_rc}" 2>/dev/null || true
        "${BB}" chmod 0644 "${shell_rc}" 2>/dev/null || true
      fi
    done
  done
}

ensure_flatpak_bootstrap() {
  # Flatpak packages can install cleanly while still being empty from a user
  # perspective. Seed the state location and the default system remote.
  "${BB}" mkdir -p "$(p /System/State/flatpak)" "$(p /var/lib)" 2>/dev/null || true
  if [ ! -e "$(p /var/lib/flatpak)" ]; then
    "${BB}" ln -s /System/State/flatpak "$(p /var/lib/flatpak)" 2>/dev/null || true
  fi
  if command -v flatpak >/dev/null 2>&1; then
    flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >>"${log_file}" 2>&1 || true
    for user_home in "$(p /Users)"/*; do
      [ -d "${user_home}" ] || continue
      owner="${user_home##*/}"
      user_flatpak_dir="${user_home}/.local/share/flatpak"
      "${BB}" mkdir -p "${user_flatpak_dir}" 2>/dev/null || true
      "${BB}" chown -R "${owner}:${owner}" "${user_home}/.local" 2>/dev/null || true
      if command -v su >/dev/null 2>&1; then
        su "${owner}" -c "HOME=${user_home} USER=${owner} LOGNAME=${owner} flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" >>"${log_file}" 2>&1 || true
      fi
    done
  fi
}

activate_rootfs() {
  rootfs="$1"
  [ -d "${rootfs}" ] || return 0
  pkg="${rootfs#$(p /Programs/)}"
  pkg="${pkg%%/*}"
  log "scan ${pkg}: ${rootfs#${ROOT}}"

  copy_tree_files "${rootfs}/usr/lib/systemd/system" "$(p /System/Compatibility/usr/lib/systemd/system)"
  copy_tree_files "${rootfs}/lib/systemd/system" "$(p /System/Compatibility/usr/lib/systemd/system)"
  copy_tree_files "${rootfs}/usr/lib/tmpfiles.d" "$(p /System/Settings/tmpfiles.d)"
  copy_tree_files "${rootfs}/usr/lib/sysusers.d" "$(p /System/Settings/sysusers.d)"
  copy_tree_files "${rootfs}/usr/share/dbus-1/system.d" "$(p /System/Settings/dbus-1/system.d)"
  copy_tree_files "${rootfs}/usr/share/dbus-1/system-services" "$(p /System/Compatibility/usr/share/dbus-1/system-services)"
  copy_tree_files "${rootfs}/usr/share/polkit-1" "$(p /System/Compatibility/usr/share/polkit-1)"
  copy_tree_files "${rootfs}/usr/lib/udev/rules.d" "$(p /System/Compatibility/usr/lib/udev/rules.d)"
  copy_tree_files "${rootfs}/lib/udev/rules.d" "$(p /System/Compatibility/lib/udev/rules.d)"
  copy_tree_files "${rootfs}/usr/lib/udev/hwdb.d" "$(p /System/Compatibility/usr/lib/udev/hwdb.d)"
  copy_tree_files "${rootfs}/lib/udev/hwdb.d" "$(p /System/Compatibility/lib/udev/hwdb.d)"
  link_or_copy "${rootfs}/usr/lib/udev/hwdb.bin" "$(p /System/Compatibility/usr/lib/udev/hwdb.bin)"
  link_or_copy "${rootfs}/lib/udev/hwdb.bin" "$(p /System/Compatibility/lib/udev/hwdb.bin)"
  link_or_copy "${rootfs}/usr/lib/udev/input_id" "$(p /System/Compatibility/usr/lib/udev/input_id)"
  link_or_copy "${rootfs}/lib/udev/input_id" "$(p /System/Compatibility/lib/udev/input_id)"
  copy_tree_files "${rootfs}/etc/pam.d" "$(p /System/Settings/pam.d)"
  copy_tree_files "${rootfs}/etc/fonts" "$(p /System/Compatibility/etc/fonts)"
  copy_tree_files "${rootfs}/usr/share/fontconfig" "$(p /System/Compatibility/usr/share/fontconfig)"
  copy_tree_files "${rootfs}/usr/share/fonts" "$(p /System/Compatibility/usr/share/fonts)"
  copy_tree_files "${rootfs}/usr/share/glib-2.0/schemas" "$(p /System/Compatibility/usr/share/glib-2.0/schemas)"
  copy_tree_files "${rootfs}/usr/share/applications" "$(p /System/Compatibility/usr/share/applications)"
  copy_tree_files "${rootfs}/usr/share/icons" "$(p /System/Compatibility/usr/share/icons)"
  copy_tree_files "${rootfs}/usr/share/mime" "$(p /System/Compatibility/usr/share/mime)"
  copy_tree_files "${rootfs}/usr/share/enlightenment" "$(p /System/Compatibility/usr/share/enlightenment)"
  copy_tree_files "${rootfs}/usr/share/elementary" "$(p /System/Compatibility/usr/share/elementary)"
  copy_tree_files "${rootfs}/usr/share/efreet" "$(p /System/Compatibility/usr/share/efreet)"
  copy_tree_files "${rootfs}/usr/share/libinput" "$(p /System/Compatibility/usr/share/libinput)"
  copy_tree_files "${rootfs}/usr/share/terminology" "$(p /System/Compatibility/usr/share/terminology)"
  copy_tree_files "${rootfs}/usr/share/locale" "$(p /System/Compatibility/usr/share/locale)"
  copy_top_level_files "${rootfs}/usr/lib/x86_64-linux-gnu" "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu)"
  copy_top_level_files "${rootfs}/lib/x86_64-linux-gnu" "$(p /System/Compatibility/lib/x86_64-linux-gnu)"
  copy_tree_files "${rootfs}/usr/lib/x86_64-linux-gnu/security" "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/security)"
  copy_tree_files "${rootfs}/lib/x86_64-linux-gnu/security" "$(p /System/Compatibility/lib/x86_64-linux-gnu/security)"
  copy_top_level_files "${rootfs}/usr/lib" "$(p /System/Compatibility/usr/lib)"
  copy_top_level_files "${rootfs}/lib" "$(p /System/Compatibility/lib)"
  copy_tree_files "${rootfs}/usr/libexec" "$(p /System/Compatibility/usr/libexec)"
  publish_libexec_wrappers "${rootfs}/usr/libexec" "$(p /System/Compatibility/usr/libexec)"
  copy_tree_files "${rootfs}/usr/lib/xorg" "$(p /System/Compatibility/usr/lib/xorg)"
  copy_tree_files "${rootfs}/usr/lib/x86_64-linux-gnu/enlightenment" "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment)"
  copy_tree_files "${rootfs}/usr/lib/x86_64-linux-gnu/evas" "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/evas)"
  copy_tree_files "${rootfs}/usr/lib/x86_64-linux-gnu/ecore_evas" "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/ecore_evas)"
  copy_tree_files "${rootfs}/usr/lib/x86_64-linux-gnu/edje" "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/edje)"
  copy_tree_files "${rootfs}/usr/lib/x86_64-linux-gnu/ecore_imf" "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/ecore_imf)"
  copy_tree_files "${rootfs}/usr/lib/x86_64-linux-gnu/elementary" "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/elementary)"
}

ensure_machine_id
ensure_core_aliases
ensure_locale_defaults

for rootfs in "$(p /Programs)"/*/*/RootFS; do
  [ -d "${rootfs}" ] || continue
  case "${rootfs}" in
    */current/RootFS) continue ;;
  esac
  activate_rootfs "${rootfs}"
done

activate_auzix_theme_assets
activate_auzix_desktop_profile_assets
ensure_sudo_pam_bootstrap
ensure_interactive_command_surface

# Keep standard aliases visible from inside AUZiX.
[ -e "$(p /etc)" ] || "${BB}" ln -s /System/Settings "$(p /etc)" 2>/dev/null || true
if [ -d "$(p /etc)" ] && [ ! -L "$(p /etc)" ]; then
  [ -e "$(p /etc/ssl)" ] || "${BB}" ln -s /System/Compatibility/etc/ssl "$(p /etc/ssl)" 2>/dev/null || true
  [ -e "$(p /etc/pki)" ] || "${BB}" ln -s /System/Compatibility/etc/pki "$(p /etc/pki)" 2>/dev/null || true
fi
[ -e "$(p /usr)" ] || "${BB}" ln -s /System/Compatibility/usr "$(p /usr)" 2>/dev/null || true
[ -e "$(p /lib)" ] || "${BB}" ln -s /System/Compatibility/lib "$(p /lib)" 2>/dev/null || true
[ -e "$(p /lib64)" ] || "${BB}" ln -s /System/Compatibility/lib64 "$(p /lib64)" 2>/dev/null || true

"${BB}" chmod 0755 "$(p /)" "$(p /System)" "$(p /System/Settings)" "$(p /System/Compatibility)" "$(p /Programs)" 2>/dev/null || true
"${BB}" chmod 1777 "$(p /tmp)" 2>/dev/null || true
"${BB}" chmod 0755 "$(p /var/cache/fontconfig)" 2>/dev/null || true

# Preserve Debian's privileged Enlightenment helper contract. Without this,
# LightDM can authenticate and E can start, but E_System/Auth paths fail or hang
# later in session startup.
for e_helper in enlightenment_system enlightenment_sys enlightenment_ckpasswd; do
  e_helper_path="$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment/utils/${e_helper})"
  if [ -f "${e_helper_path}" ]; then
    "${BB}" chown root:root "${e_helper_path}" 2>/dev/null || true
    "${BB}" chmod 4755 "${e_helper_path}" 2>/dev/null || true
  fi
done

# EFL module payloads are runtime code even though Debian stores them under
# /usr/lib data-like module directories. Make them executable after activation.
for module_root in \
  "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment)" \
  "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/evas)" \
  "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/ecore_evas)" \
  "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/edje)" \
  "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/ecore_imf)" \
  "$(p /System/Compatibility/usr/lib/x86_64-linux-gnu/elementary)"; do
  [ -d "${module_root}" ] || continue
  "${BB}" find "${module_root}" -type f \( -name '*.so' -o -perm -0100 \) -exec "${BB}" chmod 0755 {} \; 2>/dev/null || true
done

# Run low-risk triggers if their commands are available.
if command -v glib-compile-schemas >/dev/null 2>&1; then
  glib-compile-schemas /System/Compatibility/usr/share/glib-2.0/schemas >>"${log_file}" 2>&1 || true
fi
if command -v update-mime-database >/dev/null 2>&1; then
  update-mime-database /System/Compatibility/usr/share/mime >>"${log_file}" 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /System/Compatibility/usr/share/applications >>"${log_file}" 2>&1 || true
fi
if command -v fc-cache >/dev/null 2>&1; then
  fc-cache -r >>"${log_file}" 2>&1 || true
fi
ensure_flatpak_bootstrap

# Make the system font alias explicit after package activation. Xorg's config
# prefers /System/Fonts but Debian payloads land under /usr/share/fonts.
if [ -d "$(p /System/Compatibility/usr/share/fonts)" ] &&
   [ ! -e "$(p /System/Fonts/X11)" ]; then
  "${BB}" mkdir -p "$(p /System/Fonts)" 2>/dev/null || true
  "${BB}" ln -s /System/Compatibility/usr/share/fonts/X11 "$(p /System/Fonts/X11)" 2>/dev/null || true
fi

if [ -x "$(p /System/Compatibility/bin/udevadm)" ]; then
  "$(p /System/Compatibility/bin/udevadm)" trigger --action=add >>"${log_file}" 2>&1 || true
  "$(p /System/Compatibility/bin/udevadm)" settle --timeout=10 >>"${log_file}" 2>&1 || true
fi

log "done"
echo "activation-basic=done log=${log_file#${ROOT}}"
