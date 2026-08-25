#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AUZIX_DEBIAN_SUITE="${AUZIX_DEBIAN_SUITE:-trixie}"
export AUZIX_STRICT_RELEASE_LANE="${AUZIX_STRICT_RELEASE_LANE:-1}"
PROFILE="${1:-${ROOT_DIR}/profiles/packages/auzix-trixie-user-apps.packages}"
AUZIX_ROOT="${2:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
LIMIT="${AUZIX_TRIXIE_LIMIT:-0}"
OFFSET="${AUZIX_TRIXIE_OFFSET:-0}"
SORT_PROFILE="${AUZIX_TRIXIE_SORT_PROFILE:-0}"
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
[[ "${OFFSET}" =~ ^[0-9]+$ ]] || {
  log "AUZIX_TRIXIE_OFFSET must be a non-negative integer"
  exit 1
}
[[ "${SORT_PROFILE}" =~ ^[01]$ ]] || {
  log "AUZIX_TRIXIE_SORT_PROFILE must be 0 or 1"
  exit 1
}
[[ "${REPORT_NAME}" =~ ^[A-Za-z0-9._-]+[.]json$ ]] || {
  log "AUZIX_TRIXIE_REPORT must be a JSON filename"
  exit 1
}

mkdir -p "${REPORT_DIR}"
find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name 'Debian.*.auzix.json' -delete 2>/dev/null || true
rm -rf "${AUZIX_ROOT}/Programs/DebianPackages"
if [[ "${SORT_PROFILE}" == "1" ]]; then
  mapfile -t packages < <(awk 'NF && $1 !~ /^#/ {print $1}' "${PROFILE}" | sort -u)
else
  mapfile -t packages < <(awk '
    NF && $1 !~ /^#/ {
      if (!seen[$1]++) print $1
    }
  ' "${PROFILE}")
fi
if (( OFFSET > 0 )); then
  packages=("${packages[@]:OFFSET}")
fi
if (( LIMIT > 0 && LIMIT < ${#packages[@]} )); then
  packages=("${packages[@]:0:LIMIT}")
fi
log "profile_order=$([[ "${SORT_PROFILE}" == "1" ]] && printf sorted || printf preserved) package_count=${#packages[@]}"
log "strict_release_lane=${AUZIX_STRICT_RELEASE_LANE} debian_suite=${AUZIX_DEBIAN_SUITE}"

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
results_file="$(mktemp "${TMPDIR:-/tmp}/auzix-trixie-intake-results.XXXXXX.jsonl")"
trap 'rm -f "${results_file}"' EXIT
package_index=0
for package_name in "${packages[@]}"; do
  package_index=$((package_index + 1))
  package_started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  log "transaction=${package_index}/${#packages[@]} building=${package_name} dependency_discovery=${AUZIX_TRIXIE_BUILD_DEPENDS:-1}"
  status="failed"
  if "${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" \
    "${AUZIX_ROOT}" "${package_name}"; then
    status="complete"
  else
    rc=$?
    if [[ "${rc}" -eq 2 ]]; then
      status="skipped"
    else
      status="failed"
    fi
  fi
  package_finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -cn --arg id "${package_name}" --arg status "${status}" \
    --arg started_at "${package_started}" --arg finished_at "${package_finished}" \
    '{id: $id, status: $status, started_at: $started_at, finished_at: $finished_at}' \
    >>"${results_file}"
done

finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n --slurpfile results "${results_file}" \
  --arg format "auzix-trixie-intake-report-v1" \
  --arg profile "${PROFILE#${ROOT_DIR}/}" \
  --arg started_at "${started_at}" \
  --arg finished_at "${finished_at}" \
  '{
    format: $format,
    profile: $profile,
    status: (if any($results[]; .status == "failed") then "partial" else "complete" end),
    started_at: $started_at,
    finished_at: $finished_at,
    complete: ([$results[] | select(.status == "complete")] | length),
    skipped: ([$results[] | select(.status == "skipped")] | length),
    failed: ([$results[] | select(.status == "failed")] | length),
    results: $results
  }' >"${REPORT_FILE}"

log "report: ${REPORT_FILE}"
