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
path /Programs/AuzixPackageManagerEfl/current
path /Programs/Midori/current/Commands/midori
path /Programs/ApkTools/current/Commands/apk
path /Programs/Sudo/current/Commands/sudo
path /Programs/Podman/current/Commands/podman
file /System/Settings/install/apk-installer/10-alpha-minimal.list
file /System/Compatibility/usr/share/applications/auzix-installer.desktop
file /System/Compatibility/usr/share/applications/auzix-package-manager.desktop
file /System/Compatibility/usr/share/applications/auzix-midori.desktop
file /System/Compatibility/usr/share/applications/auzix-LibreOfficeWriter-libreoffice-writer.desktop
file /Users/auzix/.config/autostart/auzix-installer.desktop
file /Users/auzix/.config/autostart/auzix-browser.desktop
file /System/Compatibility/usr/share/elementary/themes/default.edj
file /System/Compatibility/usr/share/enlightenment/data/backgrounds/Foggy-Trees.edj
file /System/Compatibility/usr/share/icons/hicolor/index.theme
file /System/Compatibility/usr/share/icons/hicolor/128x128/apps/elementary.png
file /System/Compatibility/usr/share/icons/hicolor/128x128/apps/terminology.png
file /System/Compatibility/usr/share/terminology/colorschemes/Default.eet
file /System/Settings/pki/tls/certs/ca-bundle.crt
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
  lowriter --help >/dev/null
  command -v ldd >/dev/null
  command -v strings >/dev/null
  command -v stat >/dev/null
  command -v netstat >/dev/null
  command -v tail >/dev/null
  command -v vi >/dev/null
  flatpak remotes --system --columns=name | grep -qx flathub
  id auzix | grep -q "groups=.*sudo"
  id auzix | grep -q "wheel"
  sudo -n busybox id | grep -q "uid=0(root)"
  sudo -n apk --version >/dev/null
  podman --version >/dev/null
  test "$(readlink /System/Tools/launch-auzix-installer)" = \
    /Programs/AuzixInstallerEfl/current/Commands/launch-auzix-installer
  test -x /System/Tools/launch-auzix-terminal
  test -x /System/Tools/auzix-package-manager
  grep -q "/Programs/ApkTools/current/Commands/apk update" \
    /Programs/AuzixPackageManagerEfl/current/Resources/auzix-package-manager-efl.c
  grep -q "Search package names and descriptions" \
    /Programs/AuzixPackageManagerEfl/current/Resources/auzix-package-manager-efl.c
  ! grep -q "/System/Tools/auzix-pkg" \
    /Programs/AuzixPackageManagerEfl/current/Resources/auzix-package-manager-efl.c
  grep -q "/Programs/ApkTools/current/Commands/apk" \
    /Programs/AuzixInstallerEfl/current/Resources/auzix-installer-efl.c
  ! grep -q "/System/Tools/auzix-pkg" \
    /Programs/AuzixInstallerEfl/current/Resources/auzix-installer-efl.c
  grep -q "^Exec=/System/Tools/launch-auzix-installer --autostart" \
    /Users/auzix/.config/autostart/auzix-installer.desktop
  grep -q "^Exec=/System/Tools/launch-auzix-browser" \
    /Users/auzix/.config/autostart/auzix-browser.desktop
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

# Exercise a complete Flatpak transaction without pulling a graphical runtime:
# export a tiny local application, install it through a temporary remote, and
# verify that the installed ref is readable.  Flathub transport is checked by
# the separately seeded production remote.
run '
  work=/Work/Temp/flatpak-install-smoke
  rm -rf "$work"
  mkdir -p "$work/build/files/bin" "$work/repo"
  printf "%s\n" "#!/bin/sh" "echo auzix-flatpak-smoke-ok" > \
    "$work/build/files/bin/auzix-flatpak-smoke"
  chmod 0755 "$work/build/files/bin/auzix-flatpak-smoke"
  printf "%s\n" \
    "[Application]" \
    "name=com.auzix.FlatpakSmoke" \
    "runtime=org.freedesktop.Platform/x86_64/1" \
    "sdk=org.freedesktop.Sdk/x86_64/1" \
    "command=auzix-flatpak-smoke" >"$work/build/metadata"
  flatpak build-finish "$work/build" >/dev/null
  flatpak build-export "$work/repo" "$work/build" stable >/dev/null
  flatpak remote-add --system --if-not-exists --no-gpg-verify \
    auzix-validation "file://$work/repo"
  flatpak install --system --noninteractive --no-deps \
    auzix-validation com.auzix.FlatpakSmoke >/dev/null
  flatpak info --system com.auzix.FlatpakSmoke >/dev/null
  flatpak uninstall --system --noninteractive com.auzix.FlatpakSmoke >/dev/null
  flatpak remote-delete --system auzix-validation
  rm -rf "$work"
'

icon_count="$(find "$root/System/Compatibility/usr/share/icons" -type f 2>/dev/null | wc -l)"
test "$icon_count" -ge 40 || fail "icon inventory below known-good reference: $icon_count"

echo "alpha-final validation: PASS icons=$icon_count"
