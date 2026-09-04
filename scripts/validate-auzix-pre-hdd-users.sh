#!/bin/sh
set -eu

bb=/Programs/BusyBox/current/Commands/busybox
fail() { echo "pre-hdd user validation: $*" >&2; exit 1; }

# This script runs only in a disposable validation container. The codex user is
# deliberately not part of WorkstationUserPolicy or a production HDD root.
if ! grep -q '^codex:' /System/Settings/passwd; then
    adduser --disabled-password --gecos '' codex
fi
for group in sudo wheel input render netdev audio video users; do
    adduser codex "$group"
done

for user in auzix codex; do
    grep -q "^${user}:" /System/Settings/passwd || fail "missing user: $user"
    home=$($bb awk -F: -v user="$user" '$1 == user { print $6 }' /System/Settings/passwd)
    test -n "$home" && test -d "$home" || fail "$user has no home"
    id "$user" | grep -q 'sudo' || fail "$user lacks sudo"
    id "$user" | grep -q 'wheel' || fail "$user lacks wheel"
    id "$user" | grep -q 'input' || fail "$user lacks input"
    id "$user" | grep -q 'render' || fail "$user lacks render"
    id "$user" | grep -q 'netdev' || fail "$user lacks netdev"

    "$bb" su "$user" -s /System/Compatibility/bin/sh -c '
        set -eu
        test "$HOME" = "/Users/'"$user"'"
        touch "$HOME/.auzix-user-write-test"
        rm "$HOME/.auzix-user-write-test"
        for tool in ldd strings stat netstat tail vi ssh wget; do command -v "$tool" >/dev/null; done
        python3 -c "import encodings, json, os, site, ssl, subprocess"
        abiword --version >/dev/null
        lowriter --help >/dev/null
        htop --version >/dev/null
        glances --version >/dev/null
        flatpak --version >/dev/null
    '
done

echo 'pre-hdd user validation: auzix and disposable codex users passed'
