#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"

exec "${ROOT_DIR}/scripts/build-auzix-office-package.sh" "${AUZIX_ROOT}" abiword
