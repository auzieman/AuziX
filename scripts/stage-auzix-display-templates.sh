#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"

log() {
  printf '[auzix-display-templates] %s\n' "$*" >&2
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

mkdir -p \
  "${AUZIX_ROOT}/System/Settings/lightdm" \
  "${AUZIX_ROOT}/System/Tools" \
  "${AUZIX_ROOT}/Programs/Enlightenment/host/Resources/share/xsessions" \
  "${AUZIX_ROOT}/Services/display-manager"

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
sessions-directory=/Programs/Enlightenment/host/Resources/share/xsessions:/System/Compatibility/usr/share/xsessions
greeters-directory=/System/Compatibility/usr/share/xgreeters:/usr/share/xgreeters

[Seat:*]
user-session=enlightenment-auzix
session-wrapper=/System/Tools/lightdm-session-wrapper
greeter-session=lightdm-gtk-greeter
xserver-command=/System/Compatibility/bin/Xorg -config /System/Settings/X11/xorg.conf -modulepath /System/Drivers/Xorg/modules,/System/Compatibility/usr/lib/xorg/modules -logfile /System/Logs/display/Xorg-lightdm.log
EOF

cat > "${AUZIX_ROOT}/System/Tools/generate-lightdm-config" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

BB=/Programs/BusyBox/1.36.1/Commands/busybox

"${BB}" mkdir -p \
  /System/Settings/lightdm \
  /System/State/lightdm/cache \
  /System/Logs/lightdm \
  /run/lightdm

if [ -s /System/Settings/lightdm/lightdm.conf.template ]; then
  "${BB}" cp /System/Settings/lightdm/lightdm.conf.template /System/Settings/lightdm/lightdm.conf
else
  cat > /System/Settings/lightdm/lightdm.conf <<'EOF'
[LightDM]
run-directory=/run/lightdm
cache-directory=/System/State/lightdm/cache
log-directory=/System/Logs/lightdm
sessions-directory=/Programs/Enlightenment/host/Resources/share/xsessions:/System/Compatibility/usr/share/xsessions
greeters-directory=/System/Compatibility/usr/share/xgreeters:/usr/share/xgreeters

[Seat:*]
user-session=enlightenment-auzix
session-wrapper=/System/Tools/lightdm-session-wrapper
greeter-session=lightdm-gtk-greeter
xserver-command=/System/Compatibility/bin/Xorg -config /System/Settings/X11/xorg.conf -modulepath /System/Drivers/Xorg/modules,/System/Compatibility/usr/lib/xorg/modules -logfile /System/Logs/display/Xorg-lightdm.log
EOF
fi
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/generate-lightdm-config"

cat > "${AUZIX_ROOT}/System/Tools/lightdm-session-wrapper" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

export XORG_RUN_AS_USER_OK="${XORG_RUN_AS_USER_OK:-1}"
export XKB_BINDIR="${XKB_BINDIR:-/Programs/Xorg/host/Commands}"
export XKB_CONFIG_ROOT="${XKB_CONFIG_ROOT:-/System/Settings/X11/xkb}"
export XLOCALEDIR="${XLOCALEDIR:-/System/Compatibility/usr/share/X11/locale}"
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/Programs/Enlightenment/host/Resources/share:/System/Compatibility/usr/share:/usr/share}"
export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/System/Settings/xdg:/System/Compatibility/etc/xdg:/etc/xdg}"

exec "$@"
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/lightdm-session-wrapper"

cat > "${AUZIX_ROOT}/Services/display-manager/run.lightdm.disabled" <<'EOF'
#!/System/Compatibility/bin/sh
set -u

/System/Tools/generate-lightdm-config
exec /System/Compatibility/sbin/lightdm --config /System/Settings/lightdm/lightdm.conf --debug
EOF
chmod 0644 "${AUZIX_ROOT}/Services/display-manager/run.lightdm.disabled"

log "display manager templates staged under /System/Settings/lightdm"
