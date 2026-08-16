#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
PACKAGE_FILTER="${2:-}"
MODE="${3:-details}"

[[ -d "${AUZIX_ROOT}/System/PackageDB" ]] || {
  printf 'PackageDB missing: %s\n' "${AUZIX_ROOT}/System/PackageDB" >&2
  exit 1
}

jq_filter='
  def arrlen(x): if x then x | length else 0 end;
  {
    name,
    version,
    kind,
    migration_stage,
    prefix,
    current: (.paths.current // empty),
    source_package: (.source.package // empty),
    source_type: (.source.type // empty),
    depends_count: arrlen(.depends),
    recommends_count: arrlen(.recommends),
    commands,
    compatibility_exports,
    runtime_ladder,
    runtime_libraries
  }'

if [[ "${MODE}" == "summary" || "${MODE}" == "catalog" ]]; then
  receipt_glob=("${AUZIX_ROOT}/System/PackageDB"/*.auzix.json)
  printf '# AUZiX package checkpoint\n\n'
  printf '%s\n' "- root: \`${AUZIX_ROOT}\`"
  printf '%s\n' "- receipts: \`$(find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name '*.auzix.json' | wc -l)\`"
  printf '%s\n' "- command-bearing receipts: \`$(
    jq -r 'select((.commands // []) | length > 0) | .name' "${receipt_glob[@]}" 2>/dev/null | wc -l
  )\`"
  printf '%s\n' "- validation receipts: \`$(
    jq -r 'select(.validation != null) | .name' "${receipt_glob[@]}" 2>/dev/null | wc -l
  )\`"
  printf '%s\n' "- receipts declaring compatibility exports: \`$(
    jq -r 'select((.compatibility_exports // []) | length > 0) | .name' "${receipt_glob[@]}" 2>/dev/null | wc -l
  )\`"
  printf '%s\n\n' "- compatibility export paths: \`$(
    jq -r '.compatibility_exports[]?' "${receipt_glob[@]}" 2>/dev/null | sort -u | wc -l
  )\`"

  printf '## Top compatibility exporters\n\n'
  jq -r '
    select((.compatibility_exports // []) | length > 0)
    | [.name, ((.compatibility_exports // []) | length)] | @tsv
  ' "${receipt_glob[@]}" 2>/dev/null |
    sort -k2,2nr -k1,1 |
    head -40 |
    awk -F '\t' '{printf "- `%s`: %s paths\n", $1, $2}'

  printf '\n## Command-bearing packages\n\n'
  jq -r '
    select((.commands // []) | length > 0)
    | [.name, (.commands | length), (.commands | join(", "))] | @tsv
  ' "${receipt_glob[@]}" 2>/dev/null |
    sort -k1,1 |
    awk -F '\t' '{printf "- `%s`: %s command(s) — %s\n", $1, $2, $3}'

  [[ "${MODE}" == "summary" ]] && exit 0
  printf '\n---\n\n'
fi

while IFS= read -r receipt; do
  name="$(jq -r '.name // empty' "${receipt}")"
  [[ -n "${name}" ]] || continue
  if [[ -n "${PACKAGE_FILTER}" && "${name}" != *"${PACKAGE_FILTER}"* ]]; then
    continue
  fi
  printf '== %s ==\n' "${receipt#${AUZIX_ROOT}/System/PackageDB/}"
  jq "${jq_filter}" "${receipt}"
  while IFS= read -r declared_path; do
    [[ -n "${declared_path}" ]] || continue
    if [[ ! -e "${AUZIX_ROOT}${declared_path}" && ! -L "${AUZIX_ROOT}${declared_path}" ]]; then
      printf 'MISSING\t%s\n' "${declared_path}"
    fi
  done < <(
    jq -r '
      (.prefix // empty),
      (.paths.current // empty),
      .commands[]?,
      .compatibility_exports[]?,
      .runtime_libraries[]?
    ' "${receipt}"
  )
  while IFS= read -r command_path; do
    [[ -n "${command_path}" ]] || continue
    full_path="${AUZIX_ROOT}${command_path}"
    [[ -f "${full_path}" ]] || continue
    printf '%s\n' "-- wrapper: ${command_path} --"
    sed -n '1,80p' "${full_path}"
  done < <(jq -r '.commands[]?' "${receipt}")
done < <(
  find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name '*.auzix.json' | sort
)
