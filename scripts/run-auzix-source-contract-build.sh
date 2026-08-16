#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT_FILE="${1:?usage: run-auzix-source-contract-build.sh <source-contract.json> [AuzixRoot]}"
AUZIX_ROOT="${2:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
REPORT_DIR="${ROOT_DIR}/out/source-contract-builds"
CONTRACT_ID="$(jq -r '.id // .source.package // empty' "${CONTRACT_FILE}")"
REPORT_FILE="${REPORT_DIR}/${CONTRACT_ID:-source-contract}.report.json"

log() {
  printf '[auzix-source-contract-build] %s\n' "$*" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

for command_name in jq date sha256sum apt-cache; do
  command -v "${command_name}" >/dev/null 2>&1 || die "missing command: ${command_name}"
done
[[ -f "${CONTRACT_FILE}" ]] || die "contract not found: ${CONTRACT_FILE}"
[[ -d "${AUZIX_ROOT}/System/PackageDB" ]] || die "AuziX root not found: ${AUZIX_ROOT}"
[[ -x "${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" ]] ||
  die "intake script is not executable"

candidate_exists() {
  apt-cache policy "$1" 2>/dev/null |
    awk '/Candidate:/ { if ($2 != "(none)") found = 1 } END { exit found ? 0 : 1 }'
}

native_name() {
  "${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" --print-native-name "$1"
}

receipt_exists() {
  local native="$1"
  find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
    -name "${native}-*.auzix.json" -print -quit 2>/dev/null | grep -q .
}

build_one() {
  local debian_package="$1"
  local phase="$2"
  local native status started finished
  native="$(native_name "${debian_package}")"
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if receipt_exists "${native}"; then
    log "skip ${phase}: ${debian_package} -> ${native} already staged"
    status="skipped-existing"
  elif ! candidate_exists "${debian_package}"; then
    log "skip ${phase}: ${debian_package} has no apt candidate"
    status="skipped-no-candidate"
  else
    log "build ${phase}: ${debian_package} -> ${native}"
    set +e
    AUZIX_TRIXIE_BUILD_DEPENDS="${AUZIX_TRIXIE_BUILD_DEPENDS:-1}" \
    AUZIX_TRIXIE_INCLUDE_RECOMMENDS="${AUZIX_TRIXIE_INCLUDE_RECOMMENDS:-0}" \
    AUZIX_TRIXIE_OVERWRITE_NATIVE="${AUZIX_TRIXIE_OVERWRITE_NATIVE:-0}" \
      "${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" "${AUZIX_ROOT}" "${debian_package}"
    build_rc="$?"
    set -e
    if [[ "${build_rc}" == "0" ]]; then
      status="complete"
    elif [[ "${build_rc}" == "2" ]] && receipt_exists "${native}"; then
      status="skipped-existing-higher-trust"
    elif [[ "${build_rc}" == "2" ]]; then
      status="skipped-intake-policy"
    else
      status="failed"
    fi
  fi
  finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -cn --arg package "${debian_package}" --arg native "${native}" --arg phase "${phase}" \
    --arg status "${status}" --arg started_at "${started}" --arg finished_at "${finished}" \
    '{package: $package, native: $native, phase: $phase, status: $status,
      started_at: $started_at, finished_at: $finished_at}'
  [[ "${status}" != "failed" ]]
}

mapfile -t dependency_packages < <(
  jq -r '
    def dep_atoms:
      if type == "array" then .[] | dep_atoms
      elif type == "string" then .
      else empty end;
    (
      .build_queue.packages[]?.debian_package,
      .source_build.build_depends[]?,
      .debian.build_depends[]?,
      (.binary_packages[]?.depends[]? | dep_atoms),
      (.binary_packages[]?.recommends[]? | dep_atoms),
      (.debian.binary_packages[]?.depends[]? | dep_atoms),
      (.debian.binary_packages[]?.recommends[]? | dep_atoms)
    )
    | select(type == "string")
    | select(test("^[$]") | not)
  ' "${CONTRACT_FILE}" | awk '!seen[$0]++'
)

mapfile -t target_packages < <(
  jq -r '
    (.debian.binary_packages[]?.package, .binary_packages[]?.package)
    | select(type == "string")
    | select(test("^[$]") | not)
  ' "${CONTRACT_FILE}" | awk '!seen[$0]++'
)

mkdir -p "${REPORT_DIR}"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
results_file="$(mktemp)"
printf '[]\n' >"${results_file}"

log "contract: ${CONTRACT_FILE}"
log "root: ${AUZIX_ROOT}"
log "dependency packages: ${#dependency_packages[@]}"
log "target packages: ${#target_packages[@]}"

append_result() {
  local result_json="$1"
  tmp_file="$(mktemp)"
  jq --argjson result "${result_json}" '. + [$result]' "${results_file}" >"${tmp_file}"
  mv "${tmp_file}" "${results_file}"
}

overall_status="complete"
for package_name in "${dependency_packages[@]}"; do
  result_json="$(build_one "${package_name}" dependency)" || overall_status="failed"
  append_result "${result_json}"
  [[ "${overall_status}" == "complete" || "${AUZIX_SOURCE_CONTRACT_KEEP_GOING:-1}" == "1" ]] || break
done

if [[ "${overall_status}" == "complete" || "${AUZIX_SOURCE_CONTRACT_KEEP_GOING:-1}" == "1" ]]; then
  for package_name in "${target_packages[@]}"; do
    result_json="$(build_one "${package_name}" target)" || overall_status="failed"
    append_result "${result_json}"
    [[ "${overall_status}" == "complete" || "${AUZIX_SOURCE_CONTRACT_KEEP_GOING:-1}" == "1" ]] || break
  done
fi

finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n --arg format "auzix-source-contract-build-report-v1" \
  --arg contract "${CONTRACT_FILE#${ROOT_DIR}/}" \
  --arg contract_sha256 "$(sha256sum "${CONTRACT_FILE}" | awk '{print $1}')" \
  --arg root "${AUZIX_ROOT}" \
  --arg status "${overall_status}" \
  --arg started_at "${started_at}" \
  --arg finished_at "${finished_at}" \
  --argjson results "$(cat "${results_file}")" \
  '{format: $format, contract: $contract, contract_sha256: $contract_sha256,
    root: $root, status: $status, started_at: $started_at,
    finished_at: $finished_at, results: $results}' >"${REPORT_FILE}"
rm -f "${results_file}"

log "report: ${REPORT_FILE}"
[[ "${overall_status}" == "complete" ]]
