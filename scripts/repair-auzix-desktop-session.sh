#!/System/Compatibility/bin/sh
# Repair/activate the AUZiX graphical desktop contract.
# This script is intentionally safe to run repeatedly during boot, after package
# installs, or by hand on VM135-style workstation tests.
set -u

MODE="${1:-full}"

BB=${BB:-/Programs/BusyBox/current/Commands/busybox}
[ -x "${BB}" ] || BB=/Programs/BusyBox/1.36.1/Commands/busybox

PATH=/System/Compatibility/sbin:/System/Compatibility/bin:/System/Compatibility/usr/sbin:/System/Compatibility/usr/bin:/Programs/BusyBox/current/Commands:/Programs/BusyBox/1.36.1/Commands:/Programs/AuzixPackageTools/current/Commands
export PATH

LOG_DIR=/System/Logs/display
PKG_LOG_DIR=/System/Logs/packages
REPORT_DIR=/System/State/reports
REPORT=${REPORT_DIR}/desktop-session-state.json

"${BB}" mkdir -p \
  "${LOG_DIR}" "${PKG_LOG_DIR}" "${REPORT_DIR}" \
  /System/Settings/X11/xorg.conf.d \
  /System/Settings/lightdm \
  /System/Compatibility/usr/share/X11/xorg.conf.d \
  /System/Compatibility/usr/share/libinput \
  /System/Compatibility/usr/lib/udev/rules.d \
  /System/Compatibility/lib/udev/rules.d \
  /run /run/dbus /run/lightdm /run/user/1000 /run/udev /run/udev/data \
  /Users/auzix/.cache/efreet 2>/dev/null || true

log() {
  printf '[desktop-session-repair] %s\n' "$*" | "${BB}" tee -a "${LOG_DIR}/desktop-session-repair.log" >/dev/null 2>&1 || true
}

ensure_group_member() {
  group="$1"
  user="$2"
  group_file=/System/Settings/group
  [ -f "${group_file}" ] || return 0
  if "${BB}" grep -q "^${group}:" "${group_file}" &&
     ! "${BB}" grep "^${group}:" "${group_file}" | "${BB}" grep -q "\\(^\\|[, :]\\)${user}\\([, ]\\|$\\)"; then
    "${BB}" sed -i "s/^\\(${group}:[^:]*:[^:]*:\\)\\(.*\\)$/\\1\\2,${user}/" "${group_file}" 2>/dev/null || true
  fi
}

ensure_groups() {
  for user in root auzix lightdm; do
    ensure_group_member input "${user}"
    ensure_group_member video "${user}"
    ensure_group_member render "${user}"
  done
  for user in auzix lightdm; do
    ensure_group_member users "${user}"
    ensure_group_member audio "${user}"
  done
}

activate_package_surfaces() {
  if [ "${MODE}" = "--boot-fast" ] || [ "${MODE}" = "boot-fast" ]; then
    log "boot-fast: skipping broad package activation scan"
    return 0
  fi
  activation_marker=/System/State/packages/activation-basic.ok
  if [ -x /System/Tools/activate-auzix-basic-config ] &&
     { [ "${AUZIX_FORCE_PACKAGE_ACTIVATION:-0}" = "1" ] || [ ! -s "${activation_marker}" ]; }; then
    /System/Tools/activate-auzix-basic-config >>"${PKG_LOG_DIR}/desktop-session-activation.log" 2>&1 || true
    "${BB}" mkdir -p "${activation_marker%/*}" 2>/dev/null || true
    {
      echo "activated_at=$("${BB}" date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || "${BB}" date)"
      echo "force=${AUZIX_FORCE_PACKAGE_ACTIVATION:-0}"
    } >"${activation_marker}" 2>/dev/null || true
  fi

  # The activation pass must expose libinput quirks and udev rules; keep a
  # direct fallback here so existing installs can self-heal before packages are
  # rebuilt.
  for rootfs in /Programs/*/current/RootFS /Programs/*/*/RootFS; do
    [ -d "${rootfs}" ] || continue
    [ -d "${rootfs}/usr/share/libinput" ] &&
      "${BB}" cp -a "${rootfs}/usr/share/libinput/." /System/Compatibility/usr/share/libinput/ 2>/dev/null || true
    [ -d "${rootfs}/usr/lib/udev/rules.d" ] &&
      "${BB}" cp -a "${rootfs}/usr/lib/udev/rules.d/." /System/Compatibility/usr/lib/udev/rules.d/ 2>/dev/null || true
    [ -d "${rootfs}/lib/udev/rules.d" ] &&
      "${BB}" cp -a "${rootfs}/lib/udev/rules.d/." /System/Compatibility/lib/udev/rules.d/ 2>/dev/null || true
    [ -d "${rootfs}/usr/lib/udev/hwdb.d" ] &&
      "${BB}" cp -a "${rootfs}/usr/lib/udev/hwdb.d/." /System/Compatibility/usr/lib/udev/hwdb.d/ 2>/dev/null || true
    [ -f "${rootfs}/usr/lib/udev/hwdb.bin" ] &&
      "${BB}" cp -f "${rootfs}/usr/lib/udev/hwdb.bin" /System/Compatibility/usr/lib/udev/hwdb.bin 2>/dev/null || true
    [ -x "${rootfs}/usr/lib/udev/input_id" ] &&
      "${BB}" cp -f "${rootfs}/usr/lib/udev/input_id" /System/Compatibility/usr/lib/udev/input_id 2>/dev/null || true
  done

  if [ -s /System/Settings/X11/xorg.conf.d/40-libinput.conf ]; then
    "${BB}" cp -f /System/Settings/X11/xorg.conf.d/40-libinput.conf \
      /System/Compatibility/usr/share/X11/xorg.conf.d/40-libinput.conf 2>/dev/null || true
  fi
}

udev_has_input_tags() {
  [ -x /System/Compatibility/bin/udevadm ] || return 1
  for event in /dev/input/event*; do
    [ -e "${event}" ] || continue
    /System/Compatibility/bin/udevadm info --query=property --name="${event}" 2>/dev/null |
      "${BB}" grep -q '^ID_INPUT' && return 0
  done
  return 1
}

first_event_for_name() {
  pattern="$1"
  "${BB}" awk -v pat="${pattern}" '
    /^N: Name=/ { name=$0 }
    /^H: Handlers=/ && name ~ pat {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^event[0-9]+$/) {
          print "/dev/input/" $i
          exit
        }
      }
    }
  ' /proc/bus/input/devices 2>/dev/null
}

first_relative_pointer_event() {
  "${BB}" awk '
    /^N: Name=/ { event=""; has_rel=0; has_abs=0 }
    /^H: Handlers=/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^event[0-9]+$/) event="/dev/input/" $i
      }
    }
    /^B: REL=/ && $3 != "0" { has_rel=1 }
    /^B: ABS=/ && $3 != "0" { has_abs=1 }
    /^$/ {
      if (event != "" && has_rel && !has_abs) {
        print event
        exit
      }
    }
  ' /proc/bus/input/devices 2>/dev/null
}

append_input_device() {
  ident="$1"
  event="$2"
  core_opt="$3"
  [ -n "${event}" ] || return 0
  cat >> /System/Settings/X11/xorg.conf <<EOF

Section "InputDevice"
    Identifier "${ident}"
    Driver "evdev"
    Option "Device" "${event}"
    Option "${core_opt}" "true"
EndSection
EOF
}

start_udev() {
  if [ -x /Services/udev/run ]; then
    /Services/udev/run >>"${LOG_DIR}/udev-repair.log" 2>&1 || true
  elif [ -x /System/Compatibility/lib/systemd/systemd-udevd ]; then
    if ! "${BB}" ps | "${BB}" grep '[s]ystemd-udevd' >/dev/null 2>&1; then
      /System/Compatibility/lib/systemd/systemd-udevd --daemon >>"${LOG_DIR}/udev-repair.log" 2>&1 || true
    fi
    /System/Compatibility/bin/udevadm trigger --action=add >>"${LOG_DIR}/udev-repair.log" 2>&1 || true
    /System/Compatibility/bin/udevadm settle --timeout=10 >>"${LOG_DIR}/udev-repair.log" 2>&1 || true
  else
    "${BB}" mdev -s 2>/dev/null || true
  fi
}

write_lightdm_config() {
  cat > /System/Settings/lightdm/lightdm.conf.template <<'EOF'
[LightDM]
run-directory=/run/lightdm
cache-directory=/System/State/lightdm/cache
log-directory=/System/Logs/lightdm
sessions-directory=/Programs/Enlightenment/host/Resources/share/xsessions:/System/Compatibility/usr/share/xsessions:/usr/share/xsessions
greeters-directory=/System/Compatibility/usr/share/xgreeters:/usr/share/xgreeters

[Seat:*]
user-session=enlightenment-auzix
autologin-user=auzix
autologin-user-timeout=0
autologin-session=enlightenment-auzix
session-wrapper=/System/Tools/lightdm-auzix-session
greeter-session=lightdm-gtk-greeter
xserver-command=/System/Tools/auzix-xorg-realworld -modulepath /System/Drivers/Xorg/modules,/System/Compatibility/usr/lib/xorg/modules -logfile /System/Logs/display/Xorg-lightdm.log
EOF
  "${BB}" cp -f /System/Settings/lightdm/lightdm.conf.template /System/Settings/lightdm/lightdm-autologin.conf.template 2>/dev/null || true
  "${BB}" cp -f /System/Settings/lightdm/lightdm.conf.template /System/Settings/lightdm/lightdm.conf 2>/dev/null || true
}

write_xorg_libinput_config() {
  cat > /System/Settings/X11/xorg.conf <<'EOF'
Section "Files"
    ModulePath "/System/Drivers/Xorg/modules"
    ModulePath "/System/Compatibility/usr/lib/xorg/modules"
    FontPath "/System/Fonts/truetype/dejavu"
    FontPath "/System/Compatibility/usr/share/fonts/truetype/dejavu"
    FontPath "/System/Compatibility/usr/share/fonts/X11/misc"
    FontPath "/System/Compatibility/usr/share/fonts/X11/Type1"
    FontPath "/System/Compatibility/usr/share/fonts/X11/75dpi"
    FontPath "/System/Compatibility/usr/share/fonts/X11/100dpi"
EndSection

Section "ServerFlags"
    Option "AutoAddDevices" "true"
    Option "AutoEnableDevices" "true"
    Option "AllowMouseOpenFail" "true"
EndSection

Section "Device"
    Identifier "AuzixVideo"
    Driver "modesetting"
    Option "AccelMethod" "none"
    Option "DRI" "false"
EndSection

Section "Screen"
    Identifier "AuzixScreen"
    Device "AuzixVideo"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080" "1280x800" "1024x768"
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "AuzixLayout"
    Screen "AuzixScreen"
EndSection
EOF
}

write_xorg_evdev_fallback_config() {
  keyboard_event="$(first_event_for_name "AT Translated Set 2 keyboard")"
  tablet_event="$(first_event_for_name "QEMU QEMU USB Tablet")"
  mouse_event="$(first_relative_pointer_event)"
  [ -n "${mouse_event}" ] || mouse_event="$(first_event_for_name "VirtualPS/2 VMware VMMouse")"
  [ -n "${tablet_event}" ] || tablet_event="${mouse_event}"
  [ -n "${keyboard_event}" ] || keyboard_event=/dev/input/event0
  [ -n "${mouse_event}" ] || mouse_event=/dev/input/event2

  cat > /System/Settings/X11/xorg.conf <<EOF
Section "Files"
    ModulePath "/System/Drivers/Xorg/modules"
    ModulePath "/System/Compatibility/usr/lib/xorg/modules"
    FontPath "/System/Fonts/truetype/dejavu"
    FontPath "/System/Compatibility/usr/share/fonts/truetype/dejavu"
    FontPath "/System/Compatibility/usr/share/fonts/X11/misc"
    FontPath "/System/Compatibility/usr/share/fonts/X11/Type1"
    FontPath "/System/Compatibility/usr/share/fonts/X11/75dpi"
    FontPath "/System/Compatibility/usr/share/fonts/X11/100dpi"
EndSection

Section "ServerFlags"
    Option "AutoAddDevices" "false"
    Option "AutoEnableDevices" "false"
    Option "AllowMouseOpenFail" "true"
EndSection

Section "InputDevice"
    Identifier "AuzixKeyboard"
    Driver "evdev"
    Option "Device" "${keyboard_event}"
    Option "CoreKeyboard" "true"
EndSection
EOF

  append_input_device "AuzixTablet" "${tablet_event}" "CorePointer"
  layout_extra=""
  if [ "${mouse_event}" != "${tablet_event}" ]; then
    append_input_device "AuzixPointer" "${mouse_event}" "SendCoreEvents"
    layout_extra='    InputDevice "AuzixPointer" "SendCoreEvents"'
  fi

  cat >> /System/Settings/X11/xorg.conf <<EOF

Section "Device"
    Identifier "AuzixVideo"
    Driver "modesetting"
    Option "AccelMethod" "none"
    Option "DRI" "false"
EndSection

Section "Screen"
    Identifier "AuzixScreen"
    Device "AuzixVideo"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080" "1280x800" "1024x768"
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "AuzixLayout"
    Screen "AuzixScreen"
    InputDevice "AuzixKeyboard" "CoreKeyboard"
    InputDevice "AuzixTablet" "CorePointer"
${layout_extra}
EndSection
EOF
}

write_xorg_config() {
  if udev_has_input_tags; then
    XORG_INPUT_MODE=udev-libinput
    UDEV_INPUT_TAGS=true
    write_xorg_libinput_config
  else
    XORG_INPUT_MODE=evdev-explicit-fallback
    UDEV_INPUT_TAGS=false
    write_xorg_evdev_fallback_config
  fi
  log "xorg input mode=${XORG_INPUT_MODE} udev_input_tags=${UDEV_INPUT_TAGS}"
}

collect_state() {
  input_devices="$("${BB}" cat /proc/bus/input/devices 2>/dev/null | "${BB}" grep '^N: Name=' | "${BB}" sed 's/^N: Name=//; s/\"//g' | "${BB}" tr '\n' '|' | "${BB}" sed 's/|$//')"
  installed_count=0
  if [ -s /System/State/packages/installed.json ] && command -v jq >/dev/null 2>&1; then
    installed_count="$(jq '.installed | length' /System/State/packages/installed.json 2>/dev/null || echo 0)"
  fi
  cat >"${REPORT}" <<EOF
{
  "generated_at": "$("${BB}" date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || "${BB}" date)",
  "hostname": "$("${BB}" hostname 2>/dev/null || echo unknown)",
  "xorg_input_mode": "${XORG_INPUT_MODE:-unknown}",
  "udev_input_tags": ${UDEV_INPUT_TAGS:-false},
  "installed_package_count": ${installed_count},
  "input_devices": "${input_devices}",
  "lightdm_wrapper": "/System/Tools/lightdm-auzix-session",
  "notes": "Run before LightDM or after desktop package changes; re-run is safe."
}
EOF
}

ensure_groups
activate_package_surfaces
start_udev
write_lightdm_config
write_xorg_config
collect_state
log "desktop session repair complete; report=${REPORT}"
