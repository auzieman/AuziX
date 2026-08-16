#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="${1:-${ROOT_DIR}/packages/auzix-os.source.json}"
AUZIX_ROOT="${2:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"

fail() {
  printf '[auzix-os-source-contract] FAIL: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

need_cmd jq

[[ -r "${CONTRACT}" ]] || fail "missing contract ${CONTRACT}"
jq -e '.format == "auzix-os-source-contract-v1"' "${CONTRACT}" >/dev/null ||
  fail "contract format is not auzix-os-source-contract-v1"

for json_path in \
  '.root_contract.canonical_roots.system' \
  '.root_contract.canonical_roots.programs' \
  '.root_contract.compatibility_roots.usr' \
  '.bootstrap_environment.source_file' \
  '.bootstrap_environment.interactive_shim' \
  '.bootstrap_environment.exports.LD_LIBRARY_PATH' \
  '.bootstrap_environment.exports.XDG_DATA_DIRS' \
  '.archive_policy.create.numeric_owner' \
  '.archive_policy.extract.preserve_permissions'; do
  jq -e "${json_path} != null" "${CONTRACT}" >/dev/null ||
    fail "contract missing ${json_path}"
done

jq -e '.archive_policy.create.numeric_owner == true' "${CONTRACT}" >/dev/null ||
  fail "archive create policy must preserve numeric owners"
jq -e '.archive_policy.extract.preserve_permissions == true' "${CONTRACT}" >/dev/null ||
  fail "archive extract policy must preserve permissions"

source_file="$(jq -r '.bootstrap_environment.source_file' "${CONTRACT}")"
interactive_shim="$(jq -r '.bootstrap_environment.interactive_shim' "${CONTRACT}")"

if [[ -d "${AUZIX_ROOT}/System" ]]; then
  [[ -r "${AUZIX_ROOT}${source_file}" ]] ||
    fail "staged root missing ${source_file}"
  [[ -r "${AUZIX_ROOT}${interactive_shim}" ]] ||
    fail "staged root missing ${interactive_shim}"
  grep -Fq "${source_file}" "${AUZIX_ROOT}${interactive_shim}" ||
    fail "${interactive_shim} does not source ${source_file}"

  for required_lib in $(jq -r '.bootstrap_environment.exports.LD_LIBRARY_PATH[]' "${CONTRACT}"); do
    grep -Fq "${required_lib}" "${AUZIX_ROOT}${source_file}" ||
      fail "${source_file} does not export required library path ${required_lib}"
  done

  for entrypoint in \
    /System/Boot/StartSequence \
    /System/Tools/start-e \
    /System/Tools/start-enlightenment-session \
    /System/Tools/lightdm-session-wrapper \
    /System/Tools/lightdm-auzix-session \
    /System/Tools/launch-auzix-installer; do
    [[ -e "${AUZIX_ROOT}${entrypoint}" ]] || continue
    grep -Fq "${source_file}" "${AUZIX_ROOT}${entrypoint}" ||
      fail "${entrypoint} does not source ${source_file}"
  done
fi

printf '[auzix-os-source-contract] PASS: %s\n' "${CONTRACT}"
