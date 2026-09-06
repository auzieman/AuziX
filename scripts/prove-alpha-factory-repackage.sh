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
held_source=/var/lib/auzix-build/package-proof/AX-012-dcbcdda180fb
compare_from=/var/lib/auzix-build/package-proof/AX-012-3dee50cce1c6
test -s "$baseline/repository/conversion-proof.json"
test -s "$held_source/repository/conversion-proof.json"
test -s "$compare_from/repository/conversion-proof.json"
docker image inspect auzix/trixie-builder:lab --format '{{.Id}}' >"$output/trixie-builder-image.txt"
docker run --rm --network none --read-only --tmpfs /tmp \
  -e PYTHONDONTWRITEBYTECODE=1 -v "$ROOT_DIR:/workspace:ro" -w /workspace \
  auzix/trixie-builder:lab python3 -m unittest discover -s tests \
  2>&1 | tee "$output/trixie-tests.log"
printf '%s\n' "${AUZIX_SOURCE_REF:?immutable source ref required}" >"$output/source-commit.txt"
# Same original held names as r2–r5. Score this cut against r5.
jq --slurpfile proof "$held_source/repository/conversion-proof.json" \
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
  "$compare_from/repository/conversion-proof.json" "$output/repository/conversion-proof.json" \
  | tee "$output/comparison.json"
python3 "$ROOT_DIR/scripts/test-held-package-effects.py" \
  "$output/repository/conversion-proof.json" "$output/effects" --source "$ROOT_DIR" \
  2>&1 | tee "$output/effects.log"
python3 - <<'PY' "$output"
import json, sys
from pathlib import Path
out = Path(sys.argv[1])
proof = json.loads((out / "repository/conversion-proof.json").read_text())
comparison = json.loads((out / "comparison.json").read_text())
status = proof.get("status")
if status not in {"passed", "completed-with-review"}:
    raise SystemExit(f"conversion did not complete: {status}")
receipt = {
    "boundary": "intake-convert",
    "scope": "held-needed-step-wrap",
    "status": status,
    "install_tested": False,
    "hdd_locked": True,
    "newly_verified": comparison.get("newly_verified", []),
    "newly_regressed": comparison.get("newly_regressed", []),
    "findings_before": comparison.get("findings_before"),
    "findings_after": comparison.get("findings_after"),
}
(out / "validation-boundary.json").write_text(json.dumps(receipt, indent=2) + "\n")
print("INTAKE-VALIDATE", json.dumps(receipt))
print("Installation, VM, and HDD acceptance NOT tested.")
PY
