#!/bin/sh
# D-Bus configure operation, adapted from Debian 1.16.2-2 dbus.postinst.
# The caller resolves the package-owned helper and supplies an explicit
# administrator-override disposition. Do not infer absence from a missing dpkg.
set -eu
helper=${1:?package-owned helper required}
account=${2:?service account required}
override=${3:?override disposition required: present or absent}
case "$override" in
    present) echo 'dbus-helper: administrator override preserved'; exit 0 ;;
    absent) ;;
    *) echo 'dbus-helper: unresolved override policy' >&2; exit 1 ;;
esac
[ "$(id -u)" = 0 ] || { echo 'dbus-helper: root required' >&2; exit 1; }
[ ! -L "$helper" ] && [ -f "$helper" ] || {
    echo 'dbus-helper: regular non-symlink payload required' >&2; exit 1;
}
# Account creation belongs to dbus-system-bus-common, before this operation.
id "$account" >/dev/null 2>&1 || {
    echo 'dbus-helper: prerequisite service account missing' >&2; exit 1;
}
# chown can clear set-id bits; apply mode last, as dpkg-statoverride does.
chown "root:$account" "$helper"
chmod 4754 "$helper"
echo 'dbus-helper: root service-group 4754 applied'
