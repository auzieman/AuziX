#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX_PATH="${1:-${ROOT_DIR}/artifacts/auzix/repo/index.json}"

if [[ ! -s "${INDEX_PATH}" ]]; then
  printf 'repo audit: missing index: %s\n' "${INDEX_PATH}" >&2
  exit 2
fi

jq -r '
  .packages[]
  | select(.kind == "program")
  | select(((.commands // []) | length) == 0)
  | [.name, .version, (.migration_stage // ""), (.source.package // ""), (.size | tostring)]
  | @tsv
' "${INDEX_PATH}" >"${INDEX_PATH}.zero-command-programs.tsv"

count="$(wc -l <"${INDEX_PATH}.zero-command-programs.tsv" | tr -d ' ')"
if [[ "${count}" -gt 0 ]]; then
  printf 'repo audit: %s program packages have no AUZiX commands\n' "${count}" >&2
  sed -n '1,80p' "${INDEX_PATH}.zero-command-programs.tsv" >&2
fi

jq -n \
  --arg index "${INDEX_PATH}" \
  --argjson zero_command_programs "${count}" \
  '{
    format: "auzix-repo-runnability-audit-v1",
    index: $index,
    zero_command_programs: $zero_command_programs,
    status: (if $zero_command_programs == 0 then "pass" else "warn" end)
  }'
