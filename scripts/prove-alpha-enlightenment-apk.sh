#!/usr/bin/env bash
set -euo pipefail
[[ "$(hostname -s)" == r730-ai-01 || "$(hostname -s)" == lab-ai-worker ]]
source_root=$(cd "$(dirname "$0")/.." && pwd)
proof=${1:?isolated proof directory required}
candidate=/var/lib/auzix-build/pre-hdd-apk/20260905-alpha-bkc-r8
test ! -e "$proof"
mkdir -p "$proof"
python3 "$source_root/scripts/prepare-auzix-alpha-archives.py" \
  /var/lib/auzix-build/pre-hdd-apk/20260904-alpha-complete-spool \
  /var/lib/auzix-build/factory-delta/20260904-alpha-runtime-closure-r2/spool \
  "$source_root/packaging/archive-profiles/pre-hdd-missing.json" \
  "$source_root/packaging/archive-profiles/alpha-runtime-closure.json" \
  "$proof/selected" "$candidate/layer/packages"
jq '.packages=["Enlightenment"]' "$proof/selected/profile.json" >"$proof/profile.json"
docker run --rm \
  -v "$source_root/auzix:/workspace/auzix:ro" \
  -v "$source_root/packaging:/workspace/packaging:ro" \
  -v "$proof:/proof" -v "$candidate/apk-tool/apk:/tools/apk:ro" \
  auzix/package-factory:pre-hdd-20260905-alpha-bkc-r8 \
  convert-archive-profile /proof/selected /proof/profile.json /proof/output --apk-command /tools/apk
jq -e '.status=="passed" and (.packages|length)==1' "$proof/output/conversion-proof.json"
docker run --rm --network none -v "$proof/output/x86_64:/Proof:ro" \
  auzix/validation:pre-hdd-apk-20260905-alpha-bkc-r8 \
  /Programs/BusyBox/current/Commands/busybox sh -ec '
    apk add --allow-untrusted --repositories-file /dev/null /Proof/enlightenment-*.apk
    test "$(readlink /Programs/Enlightenment/current)" = /Programs/Enlightenment/0.27.1-1
    test -x /Programs/Enlightenment/current/RootFS/usr/lib/x86_64-linux-gnu/enlightenment/utils/enlightenment_system
    test -s /Programs/Enlightenment/current/RootFS/usr/lib/x86_64-linux-gnu/enlightenment/modules/appmenu/linux-gnu-x86_64-0.27.1/module.so
    enlightenment -version
    echo AX-001-apk-install-proof-pass
  ' 2>&1 | tee "$proof/install.log"
sha256sum "$proof/output/x86_64"/*.apk >"$proof/SHA256SUMS"
