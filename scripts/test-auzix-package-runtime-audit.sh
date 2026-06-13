#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT="${ROOT_DIR}/scripts/audit-auzix-package-runtime.sh"

test -x "${AUDIT}"
grep -F -- '--list "${elf}"' "${AUDIT}" >/dev/null
grep -F "grep -q 'not found'" "${AUDIT}" >/dev/null
grep -F "'.compatibility_exports[]?'" "${AUDIT}" >/dev/null
grep -F "'.runtime_libraries[]?'" "${AUDIT}" >/dev/null

echo "AuziX package runtime audit contract: PASS"
