#!/usr/bin/env bash
# Validation-era debug spine: ldd via the AUZiX glibc loader.
# Temporary for container-ladder proofs. Do not treat as identity of
# BaseLayout/BusyBox/zero. BusyBox already provides stat/strings/wget.
set -euo pipefail

OUTPUT="${1:?usage: stage-auzix-debug-tools.sh STAGING_ROOT}"
VERSION=1.0.0
STAGE="$OUTPUT"

mkdir -p \
  "$STAGE/Programs/AUZiXDebugTools/$VERSION/Commands" \
  "$STAGE/System/Compatibility/bin" \
  "$STAGE/System/PackageDB"

cat >"$STAGE/Programs/AUZiXDebugTools/$VERSION/Commands/ldd" <<'EOF'
#!/Programs/BusyBox/current/Commands/busybox sh
set -eu
[ "$#" -gt 0 ] || { echo "usage: ldd FILE..." >&2; exit 2; }
loader=
for candidate in \
  /Libraries/ld-linux-x86-64.so.2 \
  /System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2 \
  /System/Compatibility/lib64/ld-linux-x86-64.so.2
do
  if [ -x "$candidate" ] || [ -e "$candidate" ]; then
    loader=$candidate
    break
  fi
done
[ -n "$loader" ] || { echo "ldd: AUZiX runtime loader is unavailable" >&2; exit 1; }
if [ -z "${LD_LIBRARY_PATH:-}" ]; then
  LD_LIBRARY_PATH=/Libraries
  for extra in \
    /System/Libraries \
    /System/Libraries/Runtime/glibc \
    /System/Compatibility/lib64 \
    /Programs/Nginx/current/Libraries \
    /Programs/Curl/current/Libraries
  do
    [ -d "$extra" ] && LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$extra"
  done
  export LD_LIBRARY_PATH
fi
status=0
for object in "$@"; do
  [ "$#" -eq 1 ] || echo "$object:"
  "$loader" --library-path "$LD_LIBRARY_PATH" --list "$object" || status=$?
done
exit "$status"
EOF
chmod 0755 "$STAGE/Programs/AUZiXDebugTools/$VERSION/Commands/ldd"
ln -sfn /Programs/AUZiXDebugTools/$VERSION \
  "$STAGE/Programs/AUZiXDebugTools/current"
ln -sfn /Programs/AUZiXDebugTools/current/Commands/ldd \
  "$STAGE/System/Compatibility/bin/ldd"

cat >"$STAGE/System/PackageDB/AUZiXDebugTools-$VERSION.json" <<EOF
{"name":"AUZiXDebugTools","version":"$VERSION","prefix":"/Programs/AUZiXDebugTools/$VERSION","commands":["/Programs/AUZiXDebugTools/$VERSION/Commands/ldd"],"compatibility_exports":["/System/Compatibility/bin/ldd"],"notes":"Validation-era ldd wrapper. Drop from small images once the container ladder is stable."}
EOF

test -x "$STAGE/Programs/AUZiXDebugTools/$VERSION/Commands/ldd"
printf '%s\n' "$STAGE"
