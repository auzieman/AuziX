#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
LIGHTDM_VERSION="${AUZIX_LIGHTDM_VERSION:-host}"
LIGHTDM_PROGRAM="${AUZIX_ROOT}/Programs/LightDM/${LIGHTDM_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"

log() {
  printf '[auzix-lightdm] %s\n' "$*" >&2
}

require_path() {
  if [[ ! -x "$1" ]]; then
    printf 'Missing required executable: %s\n' "$1" >&2
    exit 1
  fi
}

copy_runtime_deps() {
  local binary="$1"
  local dep
  ldd "${binary}" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' | sort -u |
  while IFS= read -r dep; do
    [[ -e "${dep}" ]] || continue
    case "${dep}" in
      /lib64/*)
        install -D -m 0755 "${dep}" "${RUNTIME_LIB64}/$(basename "${dep}")"
        ;;
      /lib/x86_64-linux-gnu/*|/usr/lib/x86_64-linux-gnu/*)
        install -D -m 0755 "${dep}" "${RUNTIME_LIB}/$(basename "${dep}")"
        ;;
      /usr/lib/*|/usr/share/*)
        install -D -m 0755 "${dep}" "${AUZIX_ROOT}/System/Compatibility${dep}"
        ;;
      *)
        install -D -m 0755 "${dep}" "${AUZIX_ROOT}${dep}"
        ;;
    esac
  done
}

copy_binary() {
  local source="$1"
  local target="$2"
  install -D -m 0755 "${source}" "${target}"
  copy_runtime_deps "${source}"
}

copy_dir_if_present() {
  local source="$1"
  local target="$2"
  [[ -d "${source}" ]] || return 0
  rm -rf "${target}"
  mkdir -p "$(dirname "${target}")"
  cp -a "${source}" "${target}"
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

require_path /usr/sbin/lightdm
require_path /usr/sbin/lightdm-gtk-greeter

mkdir -p \
  "${LIGHTDM_PROGRAM}/Commands" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Compatibility/sbin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/bin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/sbin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/share" \
  "${AUZIX_ROOT}/System/Settings/lightdm" \
  "${AUZIX_ROOT}/System/Settings/pam.d" \
  "${AUZIX_ROOT}/System/State/lightdm/cache" \
  "${AUZIX_ROOT}/System/Logs/lightdm" \
  "${AUZIX_ROOT}/Services/display-manager" \
  "${AUZIX_ROOT}/Programs/Enlightenment/host/Resources/share/xsessions" \
  "${AUZIX_ROOT}/System/PackageDB" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}"

copy_binary /usr/sbin/lightdm "${LIGHTDM_PROGRAM}/Commands/lightdm"
copy_binary /usr/bin/dm-tool "${LIGHTDM_PROGRAM}/Commands/dm-tool"
copy_binary /usr/sbin/lightdm-gtk-greeter "${LIGHTDM_PROGRAM}/Commands/lightdm-gtk-greeter"

ln -sfn "/Programs/LightDM/${LIGHTDM_VERSION}/Commands/lightdm" "${AUZIX_ROOT}/System/Compatibility/sbin/lightdm"
ln -sfn "/Programs/LightDM/${LIGHTDM_VERSION}/Commands/lightdm" "${AUZIX_ROOT}/System/Compatibility/usr/sbin/lightdm"
ln -sfn "/Programs/LightDM/${LIGHTDM_VERSION}/Commands/dm-tool" "${AUZIX_ROOT}/System/Compatibility/bin/dm-tool"
ln -sfn "/Programs/LightDM/${LIGHTDM_VERSION}/Commands/dm-tool" "${AUZIX_ROOT}/System/Compatibility/usr/bin/dm-tool"
ln -sfn "/Programs/LightDM/${LIGHTDM_VERSION}/Commands/lightdm-gtk-greeter" "${AUZIX_ROOT}/System/Compatibility/bin/lightdm-gtk-greeter"
ln -sfn "/Programs/LightDM/${LIGHTDM_VERSION}/Commands/lightdm-gtk-greeter" "${AUZIX_ROOT}/System/Compatibility/usr/sbin/lightdm-gtk-greeter"

copy_dir_if_present /usr/lib/x86_64-linux-gnu/lightdm "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/lightdm"
copy_dir_if_present /usr/share/lightdm "${AUZIX_ROOT}/System/Compatibility/usr/share/lightdm"
copy_dir_if_present /usr/share/xgreeters "${AUZIX_ROOT}/System/Compatibility/usr/share/xgreeters"
copy_dir_if_present /usr/share/glib-2.0 "${AUZIX_ROOT}/System/Compatibility/usr/share/glib-2.0"
copy_dir_if_present /usr/share/icons/hicolor "${AUZIX_ROOT}/System/Compatibility/usr/share/icons/hicolor"
copy_dir_if_present /usr/share/themes/Adwaita "${AUZIX_ROOT}/System/Compatibility/usr/share/themes/Adwaita"
copy_dir_if_present /usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0 "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0"
copy_dir_if_present /usr/lib/x86_64-linux-gnu/gtk-3.0 "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/gtk-3.0"

if [[ -f /etc/dbus-1/system.d/org.freedesktop.DisplayManager.conf ]]; then
  install -D -m 0644 \
    /etc/dbus-1/system.d/org.freedesktop.DisplayManager.conf \
    "${AUZIX_ROOT}/System/Settings/dbus-1/system.d/org.freedesktop.DisplayManager.conf"
fi

find \
  "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/lightdm" \
  "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0" \
  "${AUZIX_ROOT}/System/Compatibility/usr/lib/x86_64-linux-gnu/gtk-3.0" \
  -type f -perm /111 2>/dev/null |
while IFS= read -r helper; do
  copy_runtime_deps "${helper}" || true
done

for pam_module in \
  /lib/x86_64-linux-gnu/security/pam_permit.so \
  /lib/x86_64-linux-gnu/security/pam_deny.so \
  /lib/x86_64-linux-gnu/security/pam_unix.so \
  /lib/x86_64-linux-gnu/security/pam_env.so \
  /lib/x86_64-linux-gnu/security/pam_nologin.so \
  /lib/x86_64-linux-gnu/security/pam_limits.so \
  /lib/x86_64-linux-gnu/security/pam_loginuid.so; do
  [[ -e "${pam_module}" ]] || continue
  install -D -m 0755 "${pam_module}" "${AUZIX_ROOT}/System/Compatibility${pam_module}"
  copy_runtime_deps "${pam_module}" || true
done

cat > "${AUZIX_ROOT}/Programs/Enlightenment/host/Resources/share/xsessions/enlightenment-auzix.desktop" <<'EOF'
[Desktop Entry]
Name=Enlightenment on Auzix
Comment=Start Enlightenment through the Auzix path wrapper
Exec=/System/Tools/start-enlightenment-session
TryExec=/System/Tools/start-enlightenment-session
Type=Application
DesktopNames=Enlightenment
EOF

cat > "${AUZIX_ROOT}/System/Settings/lightdm/lightdm.conf.template" <<'EOF'
[LightDM]
run-directory=/run/lightdm
cache-directory=/System/State/lightdm/cache
log-directory=/System/Logs/lightdm
sessions-directory=/Programs/Enlightenment/host/Resources/share/xsessions:/System/Compatibility/usr/share/xsessions:/usr/share/xsessions
greeters-directory=/System/Compatibility/usr/share/xgreeters:/usr/share/xgreeters

[Seat:*]
user-session=enlightenment-auzix
session-wrapper=/System/Tools/lightdm-session-wrapper
greeter-session=lightdm-gtk-greeter
xserver-command=/System/Compatibility/bin/Xorg -config /System/Settings/X11/xorg.conf -modulepath /System/Drivers/Xorg/modules,/System/Compatibility/usr/lib/xorg/modules -logfile /System/Logs/display/Xorg-lightdm.log
EOF

cat > "${AUZIX_ROOT}/System/Settings/lightdm/lightdm-autologin.conf.template" <<'EOF'
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
session-wrapper=/System/Tools/lightdm-session-wrapper
greeter-session=lightdm-gtk-greeter
xserver-command=/System/Compatibility/bin/Xorg -config /System/Settings/X11/xorg.conf -modulepath /System/Drivers/Xorg/modules,/System/Compatibility/usr/lib/xorg/modules -logfile /System/Logs/display/Xorg-lightdm.log
EOF

cat > "${AUZIX_ROOT}/System/Settings/lightdm/lightdm-gtk-greeter.conf" <<'EOF'
[greeter]
theme-name=Adwaita
icon-theme-name=hicolor
background=/System/Compatibility/usr/share/enlightenment/data/images/enlightenment.png
default-user-image=/System/Compatibility/usr/share/enlightenment/data/images/enlightenment.png
indicators=~host;~spacer;~clock;~session;~power
EOF

cat > "${AUZIX_ROOT}/System/Settings/pam.d/lightdm-greeter" <<'EOF'
#%PAM-1.0
auth required pam_permit.so
account required pam_permit.so
password required pam_deny.so
session optional pam_permit.so
EOF

cat > "${AUZIX_ROOT}/System/Settings/pam.d/lightdm-autologin" <<'EOF'
#%PAM-1.0
auth required pam_permit.so
account required pam_permit.so
password required pam_deny.so
session optional pam_permit.so
EOF

cat > "${AUZIX_ROOT}/System/Settings/pam.d/lightdm" <<'EOF'
#%PAM-1.0
auth [success=1 default=ignore] pam_unix.so nullok
auth requisite pam_deny.so
auth required pam_permit.so
account required pam_permit.so
password required pam_deny.so
session optional pam_permit.so
EOF
chmod 0644 "${AUZIX_ROOT}/System/Settings/pam.d/lightdm" \
  "${AUZIX_ROOT}/System/Settings/pam.d/lightdm-autologin" \
  "${AUZIX_ROOT}/System/Settings/pam.d/lightdm-greeter"

cat > "${AUZIX_ROOT}/System/PackageDB/LightDM-${LIGHTDM_VERSION}.auzix.json" <<EOF
{
  "name": "LightDM",
  "version": "${LIGHTDM_VERSION}",
  "kind": "service",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/LightDM/${LIGHTDM_VERSION}",
  "commands": [
    "/Programs/LightDM/${LIGHTDM_VERSION}/Commands/lightdm",
    "/Programs/LightDM/${LIGHTDM_VERSION}/Commands/lightdm-gtk-greeter",
    "/Programs/LightDM/${LIGHTDM_VERSION}/Commands/dm-tool"
  ],
  "settings": "/System/Settings/lightdm",
  "service": "/Services/display-manager",
  "notes": "LightDM GTK greeter is staged as optional; direct x11 autostart remains the default until greeter mode is selected."
}
EOF

log "LightDM runtime installed at ${LIGHTDM_PROGRAM}"
