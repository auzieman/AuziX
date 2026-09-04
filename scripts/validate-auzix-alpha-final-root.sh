#!/bin/sh
set -eu

root=${1:-/}
fail() { echo "alpha-final validation: $*" >&2; exit 1; }
path() { test -e "$root$1" || test -L "$root$1" || fail "missing $1"; }
file() { test -s "$root$1" || fail "missing or empty $1"; }
run() { chroot "$root" /Programs/BusyBox/current/Commands/busybox sh -ec "$1"; }

path /Programs/Enlightenment/current
path /Programs/Terminology/current
path /Programs/AuzixInstaller/current
path /Programs/AuzixInstallerEfl/current
path /Programs/Midori/current/Commands/midori
file /System/Compatibility/usr/share/applications/auzix-installer.desktop
file /System/Compatibility/usr/share/applications/auzix-midori.desktop
file /System/Compatibility/usr/share/applications/auzix-LibreOfficeWriter-libreoffice-writer.desktop
file /System/Compatibility/usr/share/elementary/themes/default.edj
file /System/Compatibility/usr/share/enlightenment/data/backgrounds/Foggy-Trees.edj
file /System/Compatibility/usr/share/icons/hicolor/index.theme
file /System/Compatibility/usr/share/icons/hicolor/128x128/apps/elementary.png
file /System/Compatibility/usr/share/icons/hicolor/128x128/apps/terminology.png
file /System/Settings/X11/xorg.conf.d/40-libinput.conf
file /System/Compatibility/usr/lib/udev/rules.d/60-input-id.rules
path /System/Tools/launch-auzix-installer
file /System/Tools/launch-auzix-terminal

run '
  /Programs/OpensshServer/current/Commands/sshd -T -f /System/Settings/ssh/sshd_config >/dev/null
  adduser --version >/dev/null
  python3 -c "import encodings, json, os, site, ssl, subprocess"
  enlightenment -version 2>&1 | grep -q "Version:"
  terminology --version >/dev/null
  midori --version >/dev/null
  command -v abiword >/dev/null
  command -v lowriter >/dev/null
  command -v ldd >/dev/null
  command -v strings >/dev/null
  command -v stat >/dev/null
  command -v netstat >/dev/null
  command -v tail >/dev/null
  command -v vi >/dev/null
  id auzix | grep -q "groups=.*sudo"
  test "$(readlink /System/Tools/launch-auzix-installer)" = \
    /Programs/AuzixInstallerEfl/current/Commands/launch-auzix-installer
  test -x /System/Tools/launch-auzix-terminal
  grep -q "^Exec=/System/Tools/launch-auzix-terminal" \
    /System/Compatibility/usr/share/applications/terminology.desktop
  grep -q "AUZIX_PRESTART_EFREETD:-1" \
    /System/Tools/start-enlightenment-session
  grep -q "ln -s pts/ptmx /dev/ptmx" /System/Boot/StartSequence
  grep -q "^Exec=/Programs/LibreOfficeWriter/current/Commands/lowriter" \
    /System/Compatibility/usr/share/applications/auzix-LibreOfficeWriter-libreoffice-writer.desktop
  ! grep -q "^NoDisplay=true$" \
    /System/Compatibility/usr/share/applications/auzix-LibreOfficeWriter-libreoffice-writer.desktop
'

icon_count="$(find "$root/System/Compatibility/usr/share/icons" -type f 2>/dev/null | wc -l)"
test "$icon_count" -ge 40 || fail "icon inventory below known-good reference: $icon_count"

echo "alpha-final validation: PASS icons=$icon_count"
