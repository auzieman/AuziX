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

log "staging display templates into ${AUZIX_ROOT}"

mkdir -p \
  "${AUZIX_ROOT}/System/Settings/lightdm" \
  "${AUZIX_ROOT}/System/Tools" \
  "${AUZIX_ROOT}/Programs/Enlightenment/host/Resources/share/xsessions" \
  "${AUZIX_ROOT}/Services/display-manager"
log "ensured display directories"

cat > "${AUZIX_ROOT}/Programs/Enlightenment/host/Resources/share/xsessions/enlightenment-auzix.desktop" <<'EOF'
[Desktop Entry]
Name=Enlightenment on Auzix
Comment=Start Enlightenment through the Auzix path wrapper
Exec=/System/Tools/start-enlightenment-session
TryExec=/System/Tools/start-enlightenment-session
Type=Application
DesktopNames=Enlightenment
EOF
log "wrote xsessions/enlightenment-auzix.desktop"

cat > "${AUZIX_ROOT}/System/Settings/lightdm/lightdm.conf.template" <<'EOF'
[LightDM]
run-directory=/run/lightdm
cache-directory=/System/State/lightdm/cache
log-directory=/System/Logs/lightdm
sessions-directory=/Programs/Enlightenment/host/Resources/share/xsessions:/System/Compatibility/usr/share/xsessions
greeters-directory=/System/Compatibility/usr/share/xgreeters:/usr/share/xgreeters

[Seat:*]
user-session=enlightenment-auzix
autologin-user=auzix
autologin-user-timeout=0
autologin-session=enlightenment-auzix
session-wrapper=/System/Tools/lightdm-auzix-session
greeter-session=lightdm-gtk-greeter
xserver-command=/System/Compatibility/bin/Xorg -config /System/Settings/X11/xorg.conf -modulepath /System/Drivers/Xorg/modules,/System/Compatibility/usr/lib/xorg/modules -logfile /System/Logs/display/Xorg-lightdm.log
EOF
log "wrote lightdm.conf.template"

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
autologin-user=auzix
autologin-user-timeout=0
autologin-session=enlightenment-auzix
session-wrapper=/System/Tools/lightdm-auzix-session
greeter-session=lightdm-gtk-greeter
xserver-command=/System/Compatibility/bin/Xorg -config /System/Settings/X11/xorg.conf -modulepath /System/Drivers/Xorg/modules,/System/Compatibility/usr/lib/xorg/modules -logfile /System/Logs/display/Xorg-lightdm.log
EOF
fi
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/generate-lightdm-config"
log "wrote System/Tools/generate-lightdm-config"

cat > "${AUZIX_ROOT}/System/Tools/lightdm-session-wrapper" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

[ -r /System/Settings/auzix-paths.sh ] && . /System/Settings/auzix-paths.sh
export XORG_RUN_AS_USER_OK="${XORG_RUN_AS_USER_OK:-1}"
export XKB_BINDIR="${XKB_BINDIR:-/Programs/Xorg/host/Commands}"
export XKB_CONFIG_ROOT="${XKB_CONFIG_ROOT:-/System/Settings/X11/xkb}"
export XLOCALEDIR="${XLOCALEDIR:-/System/Compatibility/usr/share/X11/locale}"

exec "$@"
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/lightdm-session-wrapper"
log "wrote System/Tools/lightdm-session-wrapper"

cat > "${AUZIX_ROOT}/System/Tools/lightdm-auzix-session" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -u

[ -r /System/Settings/auzix-paths.sh ] && . /System/Settings/auzix-paths.sh
export HOME="${HOME:-/Users/auzix}"
export USER="${USER:-auzix}"
export LOGNAME="${LOGNAME:-auzix}"
export LANG="${LANG:-en_US.UTF-8}"
export LANGUAGE="${LANGUAGE:-en_US:en}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
export XDG_SESSION_DESKTOP="${XDG_SESSION_DESKTOP:-enlightenment}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Enlightenment}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
export XKB_BINDIR="${XKB_BINDIR:-/Programs/Xorg/host/Commands}"
export XKB_CONFIG_ROOT="${XKB_CONFIG_ROOT:-/System/Settings/X11/xkb}"
export XLOCALEDIR="${XLOCALEDIR:-/System/Compatibility/usr/share/X11/locale}"
export E_DATA_DIR="${E_DATA_DIR:-/System/Compatibility/usr/share/enlightenment}"
export E_CONF_DIR="${E_CONF_DIR:-/System/Settings/desktop/enlightenment}"
export PATH="/Programs/BusyBox/current/Commands:/Programs/BusyBox/1.36.1/Commands:${PATH:-}"

BB=/Programs/BusyBox/current/Commands/busybox
[ -x "${BB}" ] || BB=/Programs/BusyBox/1.36.1/Commands/busybox

"${BB}" mkdir -p "${XDG_RUNTIME_DIR}" "${HOME}/.cache" "${HOME}/.cache/fontconfig" "${HOME}/.config" "${HOME}/.e" /var/cache/fontconfig 2>/dev/null || true
"${BB}" chown -R 1000:1000 "${XDG_RUNTIME_DIR}" "${HOME}/.cache" "${HOME}/.config" "${HOME}/.e" 2>/dev/null || true
"${BB}" chmod 0700 "${XDG_RUNTIME_DIR}" 2>/dev/null || true
"${BB}" chmod 0700 "${HOME}/.cache" "${HOME}/.cache/fontconfig" 2>/dev/null || true
"${BB}" chmod 0755 /var/cache/fontconfig 2>/dev/null || true

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  if [ ! -S "${XDG_RUNTIME_DIR}/bus" ] && command -v dbus-daemon >/dev/null 2>&1; then
    dbus-daemon --session --address="unix:path=${XDG_RUNTIME_DIR}/bus" --fork \
      >>"${HOME}/.xsession-errors" 2>&1 || true
  fi
  if [ -S "${XDG_RUNTIME_DIR}/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
  fi
fi

if [ "$#" -gt 0 ]; then
  exec "$@"
fi
exec /System/Tools/start-enlightenment-session
SCRIPT
chmod 0755 "${AUZIX_ROOT}/System/Tools/lightdm-auzix-session"
log "wrote System/Tools/lightdm-auzix-session"

cat > "${AUZIX_ROOT}/Services/display-manager/run.lightdm.disabled" <<'EOF'
#!/System/Compatibility/bin/sh
set -u

/System/Tools/generate-lightdm-config
exec /System/Compatibility/sbin/lightdm --config /System/Settings/lightdm/lightdm.conf --debug
EOF
chmod 0644 "${AUZIX_ROOT}/Services/display-manager/run.lightdm.disabled"
log "wrote Services/display-manager/run.lightdm.disabled"

log "display manager templates staged: 6 files"
