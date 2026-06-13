#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-${ROOT_DIR}/profiles/packages/auzix-trixie-user-apps.packages}"
AUZIX_ROOT="${2:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
LIMIT="${AUZIX_TRIXIE_LIMIT:-0}"
REPORT_DIR="${ROOT_DIR}/out/package-bot"
REPORT_NAME="${AUZIX_TRIXIE_REPORT:-trixie-user-apps.report.json}"
REPORT_FILE="${REPORT_DIR}/${REPORT_NAME}"

log() {
  printf '[auzix-trixie-intake] %s\n' "$*" >&2
}

[[ -f "${PROFILE}" ]] || {
  log "profile not found: ${PROFILE}"
  exit 1
}
[[ "${LIMIT}" =~ ^[0-9]+$ ]] || {
  log "AUZIX_TRIXIE_LIMIT must be a non-negative integer"
  exit 1
}
[[ "${REPORT_NAME}" =~ ^[A-Za-z0-9._-]+[.]json$ ]] || {
  log "AUZIX_TRIXIE_REPORT must be a JSON filename"
  exit 1
}

mkdir -p "${REPORT_DIR}"
mapfile -t packages < <(awk 'NF && $1 !~ /^#/ {print $1}' "${PROFILE}" | sort -u)
if (( LIMIT > 0 && LIMIT < ${#packages[@]} )); then
  packages=("${packages[@]:0:LIMIT}")
fi

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
results='[]'
for package_name in "${packages[@]}"; do
  package_started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  log "building ${package_name}"
  if "${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" \
    "${AUZIX_ROOT}" "${package_name}"; then
    status="complete"
  else
    status="failed"
  fi
  package_finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  results="$(
    jq -cn --argjson current "${results}" --arg id "${package_name}" \
      --arg status "${status}" --arg started_at "${package_started}" \
      --arg finished_at "${package_finished}" \
      '$current + [{id: $id, status: $status,
        started_at: $started_at, finished_at: $finished_at}]'
  )"
done

finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n \
  --arg format "auzix-trixie-intake-report-v1" \
  --arg profile "${PROFILE#${ROOT_DIR}/}" \
  --arg started_at "${started_at}" \
  --arg finished_at "${finished_at}" \
  --argjson results "${results}" \
  '{
    format: $format,
    profile: $profile,
    status: (if any($results[]; .status == "failed") then "partial" else "complete" end),
    started_at: $started_at,
    finished_at: $finished_at,
    complete: ([$results[] | select(.status == "complete")] | length),
    failed: ([$results[] | select(.status == "failed")] | length),
    results: $results
  }' >"${REPORT_FILE}"

log "report: ${REPORT_FILE}"
