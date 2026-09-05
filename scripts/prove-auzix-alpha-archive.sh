#!/usr/bin/env bash
set -euo pipefail
[[ "$(hostname -s)" == r730-ai-01 || "$(hostname -s)" == lab-ai-worker ]]
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prior=${1:?prior pre-HDD work directory}
package=${2:?canonical package name}
output=${3:?new proof directory}
test ! -e "$output"
test -s "$prior/selected-repo/profile.json"
mkdir -p "$output"
jq --arg package "$package" '.packages=[$package]' \
  "$prior/selected-repo/profile.json" >"$output/profile.json"
docker run --rm \
  -v "$ROOT_DIR/auzix:/workspace/auzix:ro" \
  -v "$ROOT_DIR/packaging:/workspace/packaging:ro" \
  -v "$prior/selected-repo:/delta-repo:ro" \
  -v "$prior/apk-tool/apk:/tools/apk:ro" \
  -v "$output:/proof" \
  "auzix/package-factory:pre-hdd-$(basename "$prior")" \
  convert-archive-profile /delta-repo /proof/profile.json /proof/repository \
    --apk-command /tools/apk 2>&1 | tee "$output/proof.log"
jq -e '.status == "passed" and (.packages | length) == 1' \
  "$output/repository/conversion-proof.json" >/dev/null
echo "single archive proof: PASS package=$package output=$output"
