#!/usr/bin/env bash
set -euo pipefail
[[ "$(hostname -s)" == r730-ai-01 || "$(hostname -s)" == lab-ai-worker ]]
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prior=/var/lib/auzix-build/pre-hdd-apk/20260905-alpha-bkc-r10
output=${1:?new proof directory}
test ! -e "$output"
test -s "$prior/selected-repo/profile.json"
test -x "$prior/apk-tool/apk"
mkdir -p "$output"
printf '%s\n' "${AUZIX_SOURCE_REF:?immutable source ref required}" >"$output/source-commit.txt"
cp "$prior/selected-repo/profile.json" "$output/profile.json"
docker image inspect auzix/package-factory:pre-hdd-20260905-alpha-bkc-r10 \
  --format '{{.Id}}' >"$output/factory-image.txt"
docker run --rm \
  -v "$ROOT_DIR/auzix:/workspace/auzix:ro" \
  -v "$ROOT_DIR/packaging:/workspace/packaging:ro" \
  -v "$prior/selected-repo:/delta-repo:ro" \
  -v "$prior/apk-tool/apk:/tools/apk:ro" \
  -v "$output:/proof" \
  auzix/package-factory:pre-hdd-20260905-alpha-bkc-r10 \
  convert-archive-profile /delta-repo /proof/profile.json /proof/repository \
    --apk-command /tools/apk --workers 8 2>&1 | tee "$output/proof.log"
jq -e '.status == "passed"' "$output/repository/conversion-proof.json" >/dev/null
echo 'Conversion verified; installation and VM acceptance NOT tested.'
