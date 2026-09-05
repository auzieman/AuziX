#!/Programs/BusyBox/current/Commands/busybox sh
set -eu

# Docker materializes /etc for hosts, DNS, and resolver configuration. Publish
# installed AUZiX settings into that runtime directory without replacing
# Docker-owned files.
for name in passwd group shadow gshadow subuid subgid ca-certificates.conf adduser.conf deluser.conf sudoers login.defs; do
  source=/System/Settings/$name
  target=/etc/$name
  if test -e "$source" && ! test -e "$target"; then
    ln -s "$source" "$target"
  fi
done

for name in apk ssh ssl sudoers.d pam.d; do
  source=/System/Settings/$name
  target=/etc/$name
  if test -e "$source" && ! test -e "$target"; then
    ln -s "$source" "$target"
  fi
done

if test -x /Programs/FlatpakRuntimeSupport/current/Commands/repair-var-alias; then
  /Programs/FlatpakRuntimeSupport/current/Commands/repair-var-alias
fi

exec "$@"
