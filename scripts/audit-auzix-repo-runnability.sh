#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX_PATH="${1:-${ROOT_DIR}/artifacts/auzix/repo/index.json}"
MAX_MISSING_DEPENDENCIES="${AUZIX_MAX_MISSING_DEPENDENCIES:-}"

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

jq -r '
  (.packages | map({key: .name, value: true}) | from_entries) as $names
  | .packages[]
  | .name as $package_name
  | (.depends // [])[]
  | select($names[.] != true)
  | [$package_name, .]
  | @tsv
' "${INDEX_PATH}" >"${INDEX_PATH}.missing-dependencies.tsv"

count="$(wc -l <"${INDEX_PATH}.zero-command-programs.tsv" | tr -d ' ')"
if [[ "${count}" -gt 0 ]]; then
  printf 'repo audit: %s program packages have no AUZiX commands\n' "${count}" >&2
  sed -n '1,80p' "${INDEX_PATH}.zero-command-programs.tsv" >&2
fi

missing_dependency_count="$(wc -l <"${INDEX_PATH}.missing-dependencies.tsv" | tr -d ' ')"
if [[ "${missing_dependency_count}" -gt 0 ]]; then
  printf 'repo audit: %s package dependencies are missing from the repo index\n' "${missing_dependency_count}" >&2
  sed -n '1,120p' "${INDEX_PATH}.missing-dependencies.tsv" >&2
fi

jq -n \
  --arg index "${INDEX_PATH}" \
  --argjson zero_command_programs "${count}" \
  --argjson missing_dependencies "${missing_dependency_count}" \
  '{
    format: "auzix-repo-runnability-audit-v1",
    index: $index,
    zero_command_programs: $zero_command_programs,
    missing_dependencies: $missing_dependencies,
    status: (if $zero_command_programs == 0 and $missing_dependencies == 0 then "pass" else "warn" end)
  }'

if [[ -n "${MAX_MISSING_DEPENDENCIES}" ]] &&
  [[ "${missing_dependency_count}" -gt "${MAX_MISSING_DEPENDENCIES}" ]]; then
  printf 'repo audit: missing dependency count %s exceeds limit %s\n' \
    "${missing_dependency_count}" "${MAX_MISSING_DEPENDENCIES}" >&2
  exit 1
fi
