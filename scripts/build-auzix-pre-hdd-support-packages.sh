#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:?output directory required}"
VERSION=1.0.0
DEBUG_STAGE="$OUTPUT/AUZiXDebugTools"
USER_STAGE="$OUTPUT/WorkstationUserPolicy"
PYTHON_STAGE="$OUTPUT/AUZiXPythonFrontDoors"
SERVICE_STAGE="$OUTPUT/AuzixServiceRuntime"
DESKTOP_STAGE="$OUTPUT/AuzixDesktopIntegration"
FLATPAK_STAGE="$OUTPUT/FlatpakRuntimeSupport"

mkdir -p \
  "$DEBUG_STAGE/Programs/AUZiXDebugTools/$VERSION/Commands" \
  "$DEBUG_STAGE/System/Compatibility/bin" "$DEBUG_STAGE/System/PackageDB" \
  "$USER_STAGE/Programs/WorkstationUserPolicy/$VERSION/Package/Scripts" \
  "$USER_STAGE/System/PackageDB" \
  "$PYTHON_STAGE/Programs/AUZiXPythonFrontDoors/$VERSION/Commands" \
  "$PYTHON_STAGE/System/Compatibility/bin" "$PYTHON_STAGE/System/PackageDB"

"$ROOT_DIR/scripts/build-auzix-service-runtime-package.sh" "$SERVICE_STAGE" >/dev/null
"$ROOT_DIR/scripts/build-auzix-desktop-integration-package.sh" "$DESKTOP_STAGE" >/dev/null
"$ROOT_DIR/scripts/build-auzix-flatpak-runtime-support-package.sh" "$FLATPAK_STAGE" >/dev/null

cat >"$DEBUG_STAGE/Programs/AUZiXDebugTools/$VERSION/Commands/ldd" <<'EOF'
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
  "$loader" --list "$object" || status=$?
done
exit "$status"
EOF
chmod 0755 "$DEBUG_STAGE/Programs/AUZiXDebugTools/$VERSION/Commands/ldd"
ln -s /Programs/AUZiXDebugTools/1.0.0 \
  "$DEBUG_STAGE/Programs/AUZiXDebugTools/current"
ln -s /Programs/AUZiXDebugTools/current/Commands/ldd \
  "$DEBUG_STAGE/System/Compatibility/bin/ldd"

for command in python python3; do
  ln -s /Programs/Python313Minimal/current/Commands/python3.13 \
    "$PYTHON_STAGE/Programs/AUZiXPythonFrontDoors/$VERSION/Commands/$command"
  ln -s "/Programs/AUZiXPythonFrontDoors/current/Commands/$command" \
    "$PYTHON_STAGE/System/Compatibility/bin/$command"
done
ln -s /Programs/AUZiXPythonFrontDoors/1.0.0 \
  "$PYTHON_STAGE/Programs/AUZiXPythonFrontDoors/current"

cat >"$USER_STAGE/Programs/WorkstationUserPolicy/$VERSION/Package/Scripts/after-install" <<'EOF'
#!/Programs/BusyBox/current/Commands/busybox sh
set -eu
bb=/Programs/BusyBox/current/Commands/busybox

ensure_group() {
  name=$1 gid=$2
  grep -q "^${name}:" /System/Settings/group || "$bb" addgroup -g "$gid" "$name"
}

ensure_group auzix 1000
ensure_group wheel 1100
ensure_group input 104
ensure_group render 105
ensure_group netdev 106

if ! grep -q '^auzix:' /System/Settings/passwd; then
  "$bb" adduser -D -H -u 1000 -G auzix \
    -h /Users/auzix -s /System/Compatibility/bin/sh auzix
fi
"$bb" mkdir -p /Users/auzix
"$bb" chown 1000:1000 /Users/auzix
for group in sudo wheel input render netdev audio video users; do
  grep -q "^${group}:" /System/Settings/group || {
    echo "WorkstationUserPolicy: required group is absent: $group" >&2
    exit 1
  }
  "$bb" addgroup auzix "$group"
done
grep -q '^auzix:' /System/Settings/subuid || echo 'auzix:100000:65536' >>/System/Settings/subuid
grep -q '^auzix:' /System/Settings/subgid || echo 'auzix:100000:65536' >>/System/Settings/subgid
EOF
chmod 0755 "$USER_STAGE/Programs/WorkstationUserPolicy/$VERSION/Package/Scripts/after-install"
ln -s /Programs/WorkstationUserPolicy/1.0.0 \
  "$USER_STAGE/Programs/WorkstationUserPolicy/current"

cat >"$DEBUG_STAGE/System/PackageDB/AUZiXDebugTools-$VERSION.json" <<EOF
{"name":"AUZiXDebugTools","version":"$VERSION","prefix":"/Programs/AUZiXDebugTools/$VERSION","commands":["/Programs/AUZiXDebugTools/$VERSION/Commands/ldd"],"compatibility_exports":["/System/Compatibility/bin/ldd"]}
EOF
cat >"$USER_STAGE/System/PackageDB/WorkstationUserPolicy-$VERSION.json" <<EOF
{"name":"WorkstationUserPolicy","version":"$VERSION","prefix":"/Programs/WorkstationUserPolicy/$VERSION","maintainer_surfaces":["/Programs/WorkstationUserPolicy/$VERSION/Package/Scripts/after-install"]}
EOF
cat >"$PYTHON_STAGE/System/PackageDB/AUZiXPythonFrontDoors-$VERSION.json" <<EOF
{"name":"AUZiXPythonFrontDoors","version":"$VERSION","prefix":"/Programs/AUZiXPythonFrontDoors/$VERSION","commands":["/Programs/AUZiXPythonFrontDoors/$VERSION/Commands/python","/Programs/AUZiXPythonFrontDoors/$VERSION/Commands/python3"],"compatibility_exports":["/System/Compatibility/bin/python","/System/Compatibility/bin/python3"]}
EOF

test -x "$DEBUG_STAGE/Programs/AUZiXDebugTools/$VERSION/Commands/ldd"
test -x "$USER_STAGE/Programs/WorkstationUserPolicy/$VERSION/Package/Scripts/after-install"
test -L "$PYTHON_STAGE/Programs/AUZiXPythonFrontDoors/$VERSION/Commands/python3"
test ! -e "$DEBUG_STAGE/Programs/WorkstationUserPolicy"
test ! -e "$USER_STAGE/Programs/AUZiXDebugTools"
printf '%s\n' "$DEBUG_STAGE" "$USER_STAGE" "$PYTHON_STAGE" \
  "$SERVICE_STAGE" "$DESKTOP_STAGE" "$FLATPAK_STAGE"
