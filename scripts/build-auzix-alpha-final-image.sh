#!/usr/bin/env bash
set -euo pipefail

[[ "$(hostname -s)" == "r730-ai-01" || "$(hostname -s)" == "lab-ai-worker" ]] || {
  echo "refusing local build: run on R730" >&2
  exit 2
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="${AUZIX_ALPHA_FINAL_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
WORK="${AUZIX_ALPHA_FINAL_WORK:-/var/lib/auzix-build/alpha-final/${RUN_ID}}"
BASE_IMAGE="${AUZIX_ALPHA_FINAL_BASE_IMAGE:-auzix/alpha:pre-hdd-salvage-20260831-r8}"
OUTPUT_IMAGE="${AUZIX_ALPHA_FINAL_IMAGE:-auzix/alpha:pre-hdd-final-${RUN_ID}}"
BUILD_TARGET="${AUZIX_ALPHA_FINAL_TARGET:-validation}"
SPOOL="${AUZIX_ALPHA_FINAL_SPOOL:-/var/lib/auzix-build/factory-delta/pre-hdd-runtime-repair-r3/spool}"
REFERENCE="${AUZIX_ALPHA_FINAL_REFERENCE:-/var/lib/auzix-build/pre-hdd-reference/20260831-known-good-small-moon-ca/auzix-root.squashfs}"

fail() { echo "alpha-final: $*" >&2; exit 1; }
[[ ! -e "$WORK" ]] || fail "immutable work directory exists: $WORK"
docker image inspect "$BASE_IMAGE" >/dev/null
test -d "$SPOOL/packages"
test -s "$REFERENCE"

mkdir -p "$WORK/context/overlay" "$WORK/receipts"

docker run --rm "$BASE_IMAGE" /Programs/BusyBox/current/Commands/busybox sh -c \
  'for path in /Programs/*; do echo "${path##*/}"; done' |
  sort -u >"$WORK/base-programs.txt"

if [[ -n "${AUZIX_ALPHA_FINAL_REQUIRED_ENTRIES:-}" ]]; then
  read -r -a required_repair_entries <<<"${AUZIX_ALPHA_FINAL_REQUIRED_ENTRIES}"
else
  required_repair_entries=(
    HicolorIconTheme Udev XserverXorgInputLibinput
    Libeina1t64 Libecore1 LibecoreAudio1 LibecoreBin LibecoreCon1t64
    LibecoreDrm21 LibecoreEvas1 LibecoreFb1 LibecoreFile1 LibecoreImf1
    LibecoreInput1 LibecoreIpc1 LibecoreWl21 LibecoreX1 Libedje1
    LibedjeBin Libefreet1a LibefreetBin Libeio1 Libelementary1
    LibelementaryData Libembryo1 LibembryoBin Libemotion1 Libethumb1
    LibethumbClient1 LibethumbClientBin Libevas1 Libevas1EnginesDrm
    Libevas1EnginesWayland Libevas1EnginesX Enlightenment
  )
fi
[[ "${#required_repair_entries[@]}" -gt 0 ]] || fail "required repair entry set is empty"

for entry in "${required_repair_entries[@]}"; do
  archive="$(find "$SPOOL/packages" -maxdepth 1 -type f \
    -name "${entry}-*.auzix.tar.gz" -print -quit)"
  test -s "$archive" || fail "repair archive is absent: $entry"
done

# The repair spool is a factory-emitted dependency closure, not merely a list
# of its top-level requests. Extract the complete, sorted closure so adjacent
# libraries built by dependency discovery cannot be silently omitted again.
find "$SPOOL/packages" -maxdepth 1 -type f -name '*.auzix.tar.gz' -print0 |
  sort -z >"$WORK/repair-archives.list0"
test -s "$WORK/repair-archives.list0" || fail "repair spool is empty: $SPOOL/packages"
while IFS= read -r -d '' archive; do
  program="$(tar -tzf "$archive" |
    sed -n 's#^\(\./\)\{0,1\}Programs/\([^/]*\)/.*#\2#p' |
    awk 'NR == 1 { first = $0 } END { print first }')"
  required=false
  for entry in "${required_repair_entries[@]}"; do
    [[ "$program" != "$entry" ]] || required=true
  done
  if [[ "$required" == false && -n "$program" ]] &&
    grep -Fxq "$program" "$WORK/base-programs.txt"; then
    printf '%s\t%s\n' "$program" "$archive" >>"$WORK/receipts/skipped-existing-programs.txt"
    continue
  fi
  tar --numeric-owner -xzf "$archive" -C "$WORK/context/overlay"
done <"$WORK/repair-archives.list0"
tr '\0' '\n' <"$WORK/repair-archives.list0" >"$WORK/receipts/repair-archives.txt"

# Import non-executable desktop assets plus the two AUZiX-owned installer
# programs from small-moon. The installer has not yet been emitted into the APK
# closure; its known-good AUZiX payload is therefore an explicit alpha salvage
# input. EFL, Enlightenment, Terminology and all shared libraries remain
# authoritative from the current package image and repair spool.
unsquashfs -f -d "$WORK/reference" "$REFERENCE" \
  Programs/AuzixInstaller Programs/AuzixInstallerEfl \
  Programs/DesktopAssets \
  System/PackageDB/AuzixInstaller-0.2.auzix.json \
  System/PackageDB/AuzixInstallerEfl-0.1.auzix.json \
  System/Compatibility/usr/share/applications/auzix-installer.desktop \
  System/PackageDB/DesktopAssets-auzietek.auzix.json \
  System/Compatibility/usr/share/elementary/themes \
  System/Compatibility/usr/share/enlightenment/data/backgrounds \
  System/Compatibility/usr/share/icons \
  System/Compatibility/usr/share/terminology/themes \
  Users/auzix/.e/e/backgrounds Users/auzix/.e/e/themes >/dev/null
tar --numeric-owner -C "$WORK/reference" -cf - . |
  tar --numeric-owner -C "$WORK/context/overlay" -xf -

# Docker must materialize these compatibility views. AUZiX's command wrappers
# intentionally redirect /etc writes back to /System/Settings at runtime.
seed_container="auzix-alpha-final-seed-${RUN_ID}"
docker create --name "$seed_container" "$BASE_IMAGE" >/dev/null
trap 'docker rm -f "$seed_container" >/dev/null 2>&1 || true' EXIT
mkdir -p "$WORK/context/overlay/etc/ssh"
for database in passwd group shadow gshadow; do
  docker cp "$seed_container:/System/Settings/$database" \
    "$WORK/context/overlay/etc/$database"
done
docker cp "$seed_container:/System/Settings/ssh/sshd_config" \
  "$WORK/context/overlay/etc/ssh/sshd_config"
docker rm "$seed_container" >/dev/null
trap - EXIT

cp "$ROOT_DIR/docker/release/alpha-final/Dockerfile" "$WORK/context/Dockerfile"
cp "$ROOT_DIR/docker/release/alpha-final/finalize-alpha-final.sh" "$WORK/context/"
cp "$ROOT_DIR/scripts/validate-auzix-alpha-final-root.sh" \
  "$WORK/context/validate-alpha-final-root.sh"

docker build --pull=false --target "$BUILD_TARGET" --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  -t "$OUTPUT_IMAGE" "$WORK/context"
if [[ "$BUILD_TARGET" != validation ]]; then
  echo "alpha-final: inspection image=$OUTPUT_IMAGE work=$WORK"
  exit 0
fi
docker run --rm "$OUTPUT_IMAGE" /Programs/BusyBox/current/Commands/busybox sh \
  /Work/validate-alpha-final-root /
docker image inspect --format '{{.Id}} {{.Size}}' "$OUTPUT_IMAGE" \
  >"$WORK/receipts/image.txt"
printf 'format=auzix-alpha-final-v1\nrun_id=%s\nbase_image=%s\nimage=%s\nstatus=pass\n' \
  "$RUN_ID" "$BASE_IMAGE" "$OUTPUT_IMAGE" >"$WORK/receipts/result.txt"
echo "alpha-final: PASS image=$OUTPUT_IMAGE work=$WORK"
