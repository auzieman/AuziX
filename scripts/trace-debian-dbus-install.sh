#!/bin/sh
set -eu
export DEBIAN_FRONTEND=noninteractive
dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' > /audit/debian-before.tsv
apt-get update > /audit/debian-apt-update.log 2>&1
apt-get --simulate --no-install-recommends install dbus=1.16.2-2 > /audit/debian-plan.log 2>&1
apt-get -y --no-install-recommends -o Dpkg::Options::=--debug=2 \
    install dbus=1.16.2-2 > /audit/debian-install.log 2>&1
dpkg-query -W -f='${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' > /audit/debian-after.tsv
cp /var/log/dpkg.log /audit/debian-dpkg.log
mkdir /audit/debian-controls
for file in /var/lib/dpkg/info/dbus*; do
    [ -f "$file" ] || continue
    cp "$file" /audit/debian-controls/
done
{
    getent passwd messagebus
    getent group messagebus
    stat -c '%U:%G %a %n' /usr/lib/dbus-1.0/dbus-daemon-launch-helper
    dpkg-statoverride --list /usr/lib/dbus-1.0/dbus-daemon-launch-helper
    dpkg-query -S /usr/lib/sysusers.d/dbus.conf
    cat /usr/lib/sysusers.d/dbus.conf
    if [ -S /run/dbus/system_bus_socket ]; then
        echo 'post-install-system-bus-socket=present'
    else
        echo 'post-install-system-bus-socket=absent'
    fi
} > /audit/debian-effects.log
test "$(stat -c '%U:%G %a' /usr/lib/dbus-1.0/dbus-daemon-launch-helper)" = 'root:messagebus 4754'
# Separate runtime check. The container may intentionally deny service starts.
if [ ! -S /run/dbus/system_bus_socket ]; then
    mkdir -p /run/dbus
    dbus-daemon --system --fork
    echo 'runtime-probe=explicit-daemon-start' >> /audit/debian-effects.log
fi
dbus-send --system --print-reply --dest=org.freedesktop.DBus \
    / org.freedesktop.DBus.ListNames > /audit/debian-bus-reply.log
echo 'DEBIAN-INSTALL-TRACE passed: inventory, hooks, account, permissions and bus reply retained'
