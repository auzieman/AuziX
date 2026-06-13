#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
REPORT_FILE="${ROOT_DIR}/out/package-bot/office-smoke.report.json"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
results='[]'

mkdir -p "$(dirname "${REPORT_FILE}")"
for package_name in abiword gnumeric; do
  package_started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if "${ROOT_DIR}/scripts/build-auzix-office-package.sh" "${AUZIX_ROOT}" "${package_name}"; then
    status="complete"
  else
    status="failed"
  fi
  results="$(
    jq -cn \
      --argjson current "${results}" \
      --arg id "${package_name}" \
      --arg status "${status}" \
      --arg started_at "${package_started}" \
      --arg finished_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '$current + [{
        id: $id,
        status: $status,
        started_at: $started_at,
        finished_at: $finished_at
      }]'
  )"
done

jq -n \
  --arg format "auzix-office-smoke-report-v1" \
  --arg started_at "${started_at}" \
  --arg finished_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson results "${results}" \
  '{
    format: $format,
    status: (if any($results[]; .status == "failed") then "partial" else "complete" end),
    started_at: $started_at,
    finished_at: $finished_at,
    complete: ([$results[] | select(.status == "complete")] | length),
    failed: ([$results[] | select(.status == "failed")] | length),
    results: $results
  }' >"${REPORT_FILE}"

jq -e '.status == "complete"' "${REPORT_FILE}" >/dev/null
