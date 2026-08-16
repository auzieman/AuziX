#!/usr/bin/env bash
set -euo pipefail

TRIXIE_HOST="${TRIXIE_HOST:-auzieman@192.168.1.169}"
VM135_HOST="${VM135_HOST:-root@192.168.1.198}"

log() {
  printf '[vm135-restore-desktop-surfaces] %s\n' "$*" >&2
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

paths_file="${tmpdir}/paths.txt"
cat >"${paths_file}" <<'EOF'
usr/lib/xorg/protocol.txt
usr/share/fonts/X11/misc
usr/share/fonts/X11/Type1
usr/share/fonts/X11/75dpi
usr/share/fonts/X11/100dpi
etc/xdg/menus/e-applications.menu
usr/share/enlightenment/data/config/profile.cfg
usr/share/enlightenment/data/config/default/e.cfg
usr/share/enlightenment/data/config/default/e_bindings.cfg
usr/share/enlightenment/data/config/standard/e.cfg
usr/share/enlightenment/data/config/standard/e_bindings.cfg
usr/share/xsessions/enlightenment.desktop
usr/share/dbus-1/system-services/org.freedesktop.Accounts.service
EOF

log "packing targeted Trixie desktop surfaces from ${TRIXIE_HOST}"
ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "${TRIXIE_HOST}" \
  "tar --numeric-owner -C / -cf - --files-from -" <"${paths_file}" >"${tmpdir}/desktop-surfaces.tar"

log "copying restore archive to VM135"
scp -q -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
  "${tmpdir}/desktop-surfaces.tar" "${VM135_HOST}:/tmp/desktop-surfaces.tar"

log "extracting and restoring permissions on VM135"
ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new "${VM135_HOST}" <<'REMOTE'
set -eu
BB=/Programs/BusyBox/current/Commands/busybox
[ -x "${BB}" ] || BB=/Programs/BusyBox/1.36.1/Commands/busybox

tar --numeric-owner -xf /tmp/desktop-surfaces.tar -C /

"${BB}" mkdir -p \
  /System/Compatibility/etc \
  /System/Compatibility/usr/share/fonts \
  /System/Fonts \
  /var/cache/fontconfig \
  /Users/auzix/.cache/fontconfig \
  /Users/auzix/.cache/efreet \
  /Users/auzix/.config \
  /Users/auzix/.local/share/applications \
  /var/lib/lightdm/data \
  /run/user/1000 2>/dev/null || true

[ -e /System/Compatibility/etc/xdg ] ||
  ln -s /System/Settings/xdg /System/Compatibility/etc/xdg 2>/dev/null || true
[ -e /System/Fonts/X11 ] ||
  ln -s /System/Compatibility/usr/share/fonts/X11 /System/Fonts/X11 2>/dev/null || true

"${BB}" chown -R root:root \
  /usr/lib/xorg/protocol.txt \
  /usr/share/fonts/X11 \
  /etc/xdg/menus/e-applications.menu \
  /usr/share/enlightenment/data/config \
  /usr/share/xsessions/enlightenment.desktop \
  /usr/share/dbus-1/system-services/org.freedesktop.Accounts.service 2>/dev/null || true

"${BB}" chmod 0644 \
  /usr/lib/xorg/protocol.txt \
  /etc/xdg/menus/e-applications.menu \
  /usr/share/enlightenment/data/config/profile.cfg \
  /usr/share/enlightenment/data/config/default/e.cfg \
  /usr/share/enlightenment/data/config/default/e_bindings.cfg \
  /usr/share/enlightenment/data/config/standard/e.cfg \
  /usr/share/enlightenment/data/config/standard/e_bindings.cfg \
  /usr/share/xsessions/enlightenment.desktop \
  /usr/share/dbus-1/system-services/org.freedesktop.Accounts.service 2>/dev/null || true
"${BB}" chmod 0755 \
  /usr/share/fonts/X11 \
  /usr/share/fonts/X11/misc \
  /usr/share/fonts/X11/Type1 \
  /usr/share/fonts/X11/75dpi \
  /usr/share/fonts/X11/100dpi 2>/dev/null || true

"${BB}" chown root:root /var/cache/fontconfig 2>/dev/null || true
"${BB}" chmod 0755 /var/cache/fontconfig 2>/dev/null || true
"${BB}" chown -R auzix:auzix /Users/auzix/.cache /Users/auzix/.config /Users/auzix/.local /Users/auzix/.e 2>/dev/null || true
"${BB}" chmod 0700 /Users/auzix/.cache /Users/auzix/.cache/fontconfig /Users/auzix/.config 2>/dev/null || true
"${BB}" chmod 0755 /Users/auzix/.cache/efreet /Users/auzix/.e 2>/dev/null || true
"${BB}" chown -R lightdm:lightdm /var/lib/lightdm /System/State/lightdm /System/Logs/lightdm /run/lightdm 2>/dev/null || true
"${BB}" chmod 0750 /var/lib/lightdm 2>/dev/null || true
"${BB}" chmod 0755 /var/lib/lightdm/data /System/State/lightdm /System/Logs/lightdm /run/lightdm 2>/dev/null || true
"${BB}" chown -R auzix:auzix /run/user/1000 2>/dev/null || true
"${BB}" chmod 0700 /run/user/1000 2>/dev/null || true
"${BB}" chmod 1777 /tmp /tmp/.X11-unix 2>/dev/null || true

if command -v fc-cache >/dev/null 2>&1; then
  fc-cache -r >/System/Logs/display/fc-cache-trixie-restore.log 2>&1 || true
fi

"${BB}" rm -f /tmp/desktop-surfaces.tar 2>/dev/null || true
sync

for p in \
  /usr/lib/xorg/protocol.txt \
  /usr/share/fonts/X11/misc \
  /etc/xdg/menus/e-applications.menu \
  /usr/share/enlightenment/data/config/default/e.cfg \
  /usr/share/xsessions/enlightenment.desktop \
  /usr/share/dbus-1/system-services/org.freedesktop.Accounts.service \
  /var/cache/fontconfig \
  /Users/auzix/.cache/efreet \
  /var/lib/lightdm; do
  printf '%s\t' "$p"
  "${BB}" stat -c '%a %U:%G %s %F' "$p" 2>/dev/null || echo missing
done
REMOTE

log "restore complete; restart E/session manually when ready to reload locale/cache/menu surfaces"
