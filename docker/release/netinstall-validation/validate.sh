#!/Programs/BusyBox/current/Commands/busybox sh
set -eu

installed=/System/State/apk/db/installed
test -s "$installed"

for package in file libmagic1t64 procps iproute2 openssh-client libgssapi-krb5-2; do
  grep -q "^P:$package$" "$installed"
done

/Programs/File/current/Commands/file --version >/dev/null
/Programs/Procps/current/Commands/ps --version >/dev/null
/Programs/Iproute2/current/Commands/ip -Version >/dev/null
/Programs/OpensshClient/current/Commands/ssh -V 2>&1 |
  grep -q '^OpenSSH_'

echo auzix-netinstall-validation-ok
