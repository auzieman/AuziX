#!/usr/bin/env bash
set -euo pipefail
[[ "$(hostname -s)" == r730-ai-01 || "$(hostname -s)" == lab-ai-worker ]]
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output=${1:?new audit directory}
test ! -e "$output"
mkdir -p "$output"
docker image inspect auzix/trixie-builder:lab --format '{{.Id}}' >"$output/builder-image.txt"
docker run --rm -e PYTHONDONTWRITEBYTECODE=1 -e PYTHONPATH=/workspace \
  -v "$ROOT_DIR:/workspace:ro" -w /workspace \
  -v /var/lib/auzix-build/package-proof/AX-012-376e00389e32:/baseline:ro \
  -v "$output:/audit" \
  auzix/trixie-builder:lab python3 scripts/audit-dbus-source.py \
  2>&1 | tee "$output/audit.log"
