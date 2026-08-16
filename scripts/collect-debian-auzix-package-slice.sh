#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLICE="${1:?usage: collect-debian-auzix-package-slice.sh <slice-name> <source-package> <binary-package>...}"
SOURCE_PACKAGE="${2:?usage: collect-debian-auzix-package-slice.sh <slice-name> <source-package> <binary-package>...}"
shift 2
[[ "$#" -gt 0 ]] || {
  printf 'at least one binary package is required\n' >&2
  exit 2
}

OUT_DIR="${ROOT_DIR}/out/package-slices/${SLICE}"
FRAGMENT_DIR="${OUT_DIR}/auzix-fragments"
SHELL_FRAGMENT_DIR="${OUT_DIR}/shell-fragments"
REPORT_DIR="${OUT_DIR}/reports"
mkdir -p "${FRAGMENT_DIR}" "${SHELL_FRAGMENT_DIR}" "${REPORT_DIR}"

log() {
  printf '[auzix-package-slice] %s\n' "$*" >&2
}

log "source guidebook: ${SOURCE_PACKAGE}"
"${ROOT_DIR}/scripts/inspect-debian-source-contract.sh" "${SOURCE_PACKAGE}" "${OUT_DIR}/source-guidebook"

INDEX="${OUT_DIR}/slice-index.jsonl"
: >"${INDEX}"

for binary in "$@"; do
  log "binary lifecycle: ${binary}"
  lifecycle_dir="${OUT_DIR}/lifecycle/${binary}"
  "${ROOT_DIR}/scripts/extract-debian-package-lifecycle.sh" "${binary}" "${lifecycle_dir}"
  fragment_path="${FRAGMENT_DIR}/${binary}.auzix-fragment.json"
  shell_fragment_path="${SHELL_FRAGMENT_DIR}/${binary}.shell-fragments.json"
  "${ROOT_DIR}/scripts/convert-debian-lifecycle-to-auzix-fragment.py" "${lifecycle_dir}" "${fragment_path}" >/dev/null
  "${ROOT_DIR}/scripts/extract-lifecycle-shell-fragments.py" "${lifecycle_dir}" "${shell_fragment_path}" >/dev/null
  python3 - "${fragment_path}" "${shell_fragment_path}" >>"${INDEX}" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
shell_path = pathlib.Path(sys.argv[2])
data = json.loads(path.read_text())
shell = json.loads(shell_path.read_text())
print(json.dumps({
    "package": data["package"],
    "fragment": str(path),
    "shell_fragment": str(shell_path),
    "shell_fragment_count": len(shell.get("fragments", [])),
    "version": data["source"].get("version"),
    "hooks": data["auzix_contract"]["required_install_hooks"],
    "commands": data["debian"]["commands"][:8],
    "surfaces": [k for k, v in data["auzix_contract"]["lifecycle_surfaces"].items() if v],
}, sort_keys=True))
PY
done

{
  printf '# AUZiX package slice: %s\n\n' "${SLICE}"
  printf -- '- source_package: `%s`\n' "${SOURCE_PACKAGE}"
  printf -- '- generated_at: `%s`\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf -- '- source_guidebook: `%s`\n' "${OUT_DIR}/source-guidebook/report/guidebook.md"
  printf -- '- fragments: `%s`\n\n' "${FRAGMENT_DIR}"
  printf -- '- shell_fragments: `%s`\n\n' "${SHELL_FRAGMENT_DIR}"
  printf '## Packages\n\n'
  while IFS= read -r line; do
    python3 - "$line" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
print(f"- `{data['package']}`")
if data["commands"]:
    print(f"  - commands: {', '.join(data['commands'])}")
if data["hooks"]:
    print(f"  - hooks: {', '.join(data['hooks'])}")
if data["shell_fragment_count"]:
    print(f"  - shell fragments: {data['shell_fragment_count']}")
if data["surfaces"]:
    print(f"  - surfaces: {', '.join(data['surfaces'])}")
PY
  done <"${INDEX}"
} >"${REPORT_DIR}/slice.md"

log "slice report: ${REPORT_DIR}/slice.md"
log "slice index: ${INDEX}"
