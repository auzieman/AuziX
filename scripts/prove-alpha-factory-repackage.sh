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
baseline=/var/lib/auzix-build/package-proof/AX-012-376e00389e32
test -s "$baseline/repository/conversion-proof.json"
docker image inspect auzix/trixie-builder:lab --format '{{.Id}}' >"$output/trixie-builder-image.txt"
docker run --rm --network none --read-only --tmpfs /tmp \
  -e PYTHONDONTWRITEBYTECODE=1 -v "$ROOT_DIR:/workspace:ro" -w /workspace \
  auzix/trixie-builder:lab python3 -m unittest discover -s tests \
  2>&1 | tee "$output/trixie-tests.log"
printf '%s\n' "${AUZIX_SOURCE_REF:?immutable source ref required}" >"$output/source-commit.txt"
jq --slurpfile proof "$baseline/repository/conversion-proof.json" \
  '.name="alpha-held-bml" | .packages=[$proof[0].packages[] | select(.status=="needs-review") | .name]' \
  "$baseline/inputs/profile.json" >"$output/profile.json"
docker image inspect auzix/package-factory:pre-hdd-20260905-alpha-bkc-r10 \
  --format '{{.Id}}' >"$output/factory-image.txt"
docker run --rm \
  -v "$ROOT_DIR/auzix:/workspace/auzix:ro" \
  -v "$ROOT_DIR/packaging:/workspace/packaging:ro" \
  -v "$baseline/inputs:/delta-repo:ro" \
  -v "$prior/apk-tool/apk:/tools/apk:ro" \
  -v "$output:/proof" \
  auzix/package-factory:pre-hdd-20260905-alpha-bkc-r10 \
  convert-archive-profile /delta-repo /proof/profile.json /proof/repository \
    --apk-command /tools/apk --workers 8 2>&1 | tee "$output/proof.log"
python3 "$ROOT_DIR/scripts/compare-repackage-findings.py" \
  "$baseline/repository/conversion-proof.json" "$output/repository/conversion-proof.json" \
  | tee "$output/comparison.json"
jq -e '.status == "passed"' "$output/repository/conversion-proof.json" >/dev/null
echo 'Conversion verified; installation and VM acceptance NOT tested.'
