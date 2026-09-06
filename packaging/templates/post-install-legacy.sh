#!/Programs/BusyBox/1.36.1/Commands/busybox sh
# First-boot leftover inventory. Do not run Package/legacy or catalog scripts.
# Those are Debian leftovers kept so later conversion can read them.
set -u
BB=/Programs/BusyBox/1.36.1/Commands/busybox
LOG=/System/Logs/legacy-leftovers.receipt
CATALOG=/System/Settings/legacy-leftovers
$BB mkdir -p /System/Logs /System/State/install
{
  echo "format=auzix-legacy-leftover-receipt-v1"
  echo "executed=false"
  if [ -f "$CATALOG/index.json" ]; then
    echo "catalog=$CATALOG/index.json"
  fi
  for path in /Programs/*/current/Package/legacy/* "$CATALOG"/*/*; do
    [ -f "$path" ] || continue
    echo "artifact=$path"
  done
} >"$LOG"
# Service files named by leftover comments. apk does not start them;
# StartSequence walks /Services/*/run.
for spec in acpid:/Programs/Acpid glances:/Programs/Glances fstrim:/Programs/UtilLinux; do
  name=${spec%%:*}
  prefix=${spec#*:}
  dest=/Services/$name/run
  [ -e "$dest" ] && continue
  [ -d "$prefix" ] || continue
  $BB mkdir -p "/Services/$name"
  if [ -f /System/Settings/legacy-leftovers/service-run.sh ]; then
    $BB sed "s/@NAME@/$name/g; s|@PACKAGE_ROOT@|$prefix/current|" \
      /System/Settings/legacy-leftovers/service-run.sh >"$dest"
    $BB chmod 0755 "$dest"
    echo "ensured-service=$dest" >>"$LOG"
  fi
done
echo "[PostInstall] leftover inventory written $LOG"
