#!/bin/sh
set -eu

root=${1:-/}
fail() { echo "pre-hdd validation: $*" >&2; exit 1; }
exists() { test -e "$root$1" || test -L "$root$1" || fail "missing $1"; }
nonempty() { test -s "$root$1" || fail "missing or empty $1"; }
executable() {
    chroot "$root" /System/Compatibility/bin/sh -c 'test -x "$1"' sh "$1" \
        || fail "not executable: $1"
}

# APK registration and package lifecycle evidence.
nonempty /System/State/apk/db/installed
grep -q '^P:openssh-server$' "$root/System/State/apk/db/installed" \
    || fail "openssh-server is not registered by apk"
grep -q '^P:openssh-client$' "$root/System/State/apk/db/installed" \
    || fail "openssh-client is not registered by apk"
grep -q '^root:' "$root/System/Settings/passwd" || fail "missing root identity"
grep -q '^sshd:' "$root/System/Settings/passwd" || fail "missing sshd identity"
grep -q '^auzix:' "$root/System/Settings/passwd" || fail "missing workstation identity"
! grep -q '^glances:' "$root/System/Settings/passwd" \
    || fail "Glances application created a service identity"
test ! -e "$root/Services/glances/run" \
    || fail "Glances application created a service runner"
nonempty /System/Settings/ssh/sshd_config
nonempty /System/State/ssh/ssh_host_rsa_key
nonempty /System/State/ssh/ssh_host_ecdsa_key
nonempty /System/State/ssh/ssh_host_ed25519_key
executable /Services/ssh/run

# Promised CLI surface.
executable /Programs/BusyBox/current/Commands/busybox
executable /Programs/ApkTools/current/Commands/apk
executable /System/Compatibility/bin/apk
executable /System/Compatibility/bin/sudo
executable /Programs/Podman/current/Commands/podman
executable /Programs/AuzixServiceRuntime/current/Commands/ensure-runtime-mounts
executable /Programs/AuzixDesktopIntegration/current/Commands/activate
executable /Programs/FlatpakRuntimeSupport/current/Commands/repair-var-alias
executable /Programs/Htop/current/Commands/htop
executable /Programs/Glances/current/Commands/glances
executable /Programs/Flatpak/current/Commands/flatpak
executable /Programs/Midori/current/Commands/midori
executable /Programs/AuzixInstaller/current/Commands/launch-auzix-installer
executable /Programs/AuzixInstallerEfl/current/Commands/efl
executable /Programs/AuzixPackageManagerEfl/current/Commands/efl
executable /System/Tools/auzix-package-manager
test -s "$root/System/Compatibility/usr/share/applications/auzix-installer.desktop" \
    || fail "AUZiX installer desktop entry is absent"
test -s "$root/System/Compatibility/usr/share/applications/auzix-package-manager.desktop" \
    || fail "AUZiX package manager desktop entry is absent"
test -s "$root/System/Compatibility/usr/share/applications/auzix-midori.desktop" \
    || fail "Midori desktop entry is absent"
test -s "$root/System/Compatibility/usr/share/elementary/themes/default.edj" \
    || fail "AUZiX default theme is absent"
test -s "$root/System/Compatibility/usr/share/enlightenment/data/backgrounds/Foggy-Trees.edj" \
    || fail "Foggy Trees wallpaper is absent"
test -s "$root/System/Compatibility/usr/share/terminology/colorschemes/Default.eet" \
    || fail "Terminology data package did not publish its default colorscheme"
executable /System/Tools/launch-auzix-terminal
test "$(readlink "$root/System/Tools/launch-auzix-installer")" = \
    /Programs/AuzixInstallerEfl/current/Commands/launch-auzix-installer \
    || fail "AUZiX installer launcher does not select the EFL frontend"
executable /Programs/OpensshClient/current/Commands/ssh
executable /Programs/OpensshServer/current/Commands/sshd
executable /System/Compatibility/usr/lib/openssh/sshd-session
executable /System/Compatibility/usr/lib/openssh/sshd-auth
executable /System/Compatibility/bin/gtk4-update-icon-cache
executable /System/Compatibility/bin/ldd
executable /System/Compatibility/bin/python
executable /System/Compatibility/bin/python3

# Known r8 tail. Packages must publish these links and lifecycle scripts must
# generate caches; this validator deliberately does not repair them.
exists /Programs/Terminology/current
exists /Libraries/libebook-contacts-1.2.so.4
exists /Libraries/librtmp.so.1
exists /Libraries/libgobject-2.0.so.0
nonempty /System/Compatibility/usr/share/mime/mime.cache
grep -q '^P:gtk-update-icon-cache$' "$root/System/State/apk/db/installed" \
    || fail "gtk-update-icon-cache is not registered by apk"
grep -q '^P:hicolor-icon-theme$' "$root/System/State/apk/db/installed" \
    || fail "hicolor-icon-theme is not registered by apk"

# Execute within the package-installed root, never against Alpine tooling.
chroot "$root" /Programs/OpensshServer/current/Commands/sshd -t
chroot "$root" /Programs/BusyBox/current/Commands/busybox sh -ec '
    ssh -V 2>&1 | grep -q OpenSSH
    ps auxw >/dev/null
    htop --version >/dev/null
    glances --version >/dev/null
    flatpak --version >/dev/null
    command -v abiword >/dev/null
    command -v midori >/dev/null
    command -v curl >/dev/null
    command -v loweb >/dev/null
    command -v lowriter >/dev/null
    command -v localc >/dev/null
    command -v loimpress >/dev/null
    command -v terminology >/dev/null
    command -v enlightenment_start >/dev/null
    abiword --version >/dev/null
    lowriter --help >/dev/null
    adduser --version >/dev/null
    adduser --system --no-create-home auzix-validation >/dev/null
    id auzix-validation >/dev/null
    deluser auzix-validation >/dev/null
    ! grep -q "^auzix-validation:" /System/Settings/passwd
    ldd /Programs/BusyBox/current/Commands/busybox | grep -q libc.so
    python3 -c "import encodings, json, os, site, ssl, subprocess"
    for tool in strings stat netstat tail vi; do command -v "$tool" >/dev/null; done
    id auzix | grep -q "groups=.*sudo"
    id auzix | grep -q "wheel"
    sudo -n busybox id | grep -q "uid=0(root)"
    sudo -n apk --version >/dev/null
    podman --version >/dev/null
    /System/Tools/auzix-install-root-from-repo-profile --preflight \
      --repo https://auzix-repo.test:8443 >/dev/null
'

echo "pre-hdd validation: package-installed root passed"
