#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUEUE_FILE="${1:-${ROOT_DIR}/packages/installer-ui.queue.json}"
BATCH_ID="${2:-installer-ui-core}"
AUZIX_ROOT="${3:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
SOURCE_CATALOG="${4:-${ROOT_DIR}/packages/installer-ui.sources.json}"
REPORT_DIR="${ROOT_DIR}/out/package-bot"
REPORT_FILE="${REPORT_DIR}/${BATCH_ID}.report.json"

log() {
  printf '[auzix-package-bot] %s\n' "$*" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

for command_name in jq sha256sum date; do
  command -v "${command_name}" >/dev/null 2>&1 || die "missing command: ${command_name}"
done

[[ -f "${QUEUE_FILE}" ]] || die "queue file not found: ${QUEUE_FILE}"
[[ -f "${SOURCE_CATALOG}" ]] || die "source catalog not found: ${SOURCE_CATALOG}"
[[ -d "${AUZIX_ROOT}/System" ]] || die "AuziX root not found: ${AUZIX_ROOT}"

jq -e '
  .format == "auzix-package-build-queue-v1"
  and (.batches | type == "array")
  and all(.batches[]; (.id | type == "string") and (.packages | type == "array"))
' "${QUEUE_FILE}" >/dev/null || die "invalid queue contract"
jq -e --arg batch "${BATCH_ID}" 'any(.batches[]; .id == $batch)' "${QUEUE_FILE}" >/dev/null ||
  die "batch not found: ${BATCH_ID}"
jq -e '
  .format == "auzix-package-source-catalog-v1"
  and ([.packages[].id] | length == (unique | length))
' "${SOURCE_CATALOG}" >/dev/null || die "invalid source catalog contract"

mapfile -t package_rows < <(
  jq -r --arg batch "${BATCH_ID}" '
    .batches[] | select(.id == $batch) | .packages[]
    | select(.state == "ready") | [.id, (.script // "")] | @tsv
  ' "${QUEUE_FILE}"
)
[[ "${#package_rows[@]}" -gt 0 ]] || die "batch has no ready packages: ${BATCH_ID}"

mkdir -p "${REPORT_DIR}"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
queue_sha256="$(sha256sum "${QUEUE_FILE}" | awk '{print $1}')"
results='[]'

for row in "${package_rows[@]}"; do
  IFS=$'\t' read -r package_id script_path <<<"${row}"
  source_definition="$(
    jq -c --arg id "${package_id}" '.packages[] | select(.id == $id)' "${SOURCE_CATALOG}"
  )"
  [[ -n "${source_definition}" ]] || die "source definition not found: ${package_id}"
  catalog_script="$(jq -r '.build.script // ""' <<<"${source_definition}")"
  receipt_glob="$(jq -r '.recipe.receipt_glob // ""' <<<"${source_definition}")"
  [[ "${catalog_script}" == "${script_path}" ]] ||
    die "queue/catalog script mismatch for ${package_id}"
  case "${script_path}" in
    scripts/build-auzix-*-package.sh) ;;
    *) die "package ${package_id} has a non-allowlisted script: ${script_path}" ;;
  esac
  [[ -x "${ROOT_DIR}/${script_path}" ]] || die "package script is not executable: ${script_path}"

  package_started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  log "building ${package_id} with ${script_path}"
  if "${ROOT_DIR}/${script_path}" "${AUZIX_ROOT}"; then
    if find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -name "${receipt_glob}" -print -quit |
      grep -q .; then
      package_status="complete"
    else
      log "package ${package_id} did not produce ${receipt_glob}"
      package_status="failed"
    fi
  else
    package_status="failed"
  fi
  package_finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  results="$(
    jq -cn --argjson current "${results}" --arg id "${package_id}" \
      --arg script "${script_path}" --arg status "${package_status}" \
      --argjson definition "${source_definition}" \
      --arg started_at "${package_started}" --arg finished_at "${package_finished}" \
      '$current + [{id: $id, script: $script, status: $status,
        source: $definition.source, recipe: $definition.recipe,
        started_at: $started_at, finished_at: $finished_at}]'
  )"
  [[ "${package_status}" == "complete" ]] || break
done

finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
overall_status="$(jq -r 'if all(.[]; .status == "complete") then "complete" else "failed" end' <<<"${results}")"
jq -n --arg format "auzix-package-build-report-v1" --arg batch "${BATCH_ID}" \
  --arg queue "${QUEUE_FILE#${ROOT_DIR}/}" --arg queue_sha256 "${queue_sha256}" \
  --arg source_catalog "${SOURCE_CATALOG#${ROOT_DIR}/}" \
  --arg source_catalog_sha256 "$(sha256sum "${SOURCE_CATALOG}" | awk '{print $1}')" \
  --arg status "${overall_status}" --arg started_at "${started_at}" \
  --arg finished_at "${finished_at}" --arg root "${AUZIX_ROOT}" \
  --argjson results "${results}" \
  '{format: $format, batch: $batch, queue: $queue, queue_sha256: $queue_sha256,
    source_catalog: $source_catalog, source_catalog_sha256: $source_catalog_sha256,
    status: $status, started_at: $started_at, finished_at: $finished_at,
    root: $root, results: $results}' >"${REPORT_FILE}"

log "report: ${REPORT_FILE}"
[[ "${overall_status}" == "complete" ]]
