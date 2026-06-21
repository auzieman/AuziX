#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${1:-${ROOT_DIR}/packages/source-workbench.seed.json}"
WORK_ROOT="${AUZIX_WORKBENCH_ROOT:-${ROOT_DIR}}"
REPORT_DIR="${AUZIX_WORKBENCH_REPORT_DIR:-${WORK_ROOT}/out/source-workbench}"

log() {
  printf '[source-workbench] %s\n' "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

require_cmd jq

if [[ ! -s "${MANIFEST}" ]]; then
  printf 'Source workbench manifest not found: %s\n' "${MANIFEST}" >&2
  exit 1
fi

mkdir -p "${REPORT_DIR}"

summary_path="${REPORT_DIR}/boot-summary.json"
plan_path="${REPORT_DIR}/build-plan.txt"

format="$(jq -r '.format' "${MANIFEST}")"
if [[ "${format}" != "auzix-source-workbench-v1" ]]; then
  printf 'Unsupported source workbench format: %s\n' "${format}" >&2
  exit 1
fi

sources_root="$(jq -r '.defaults.roots.sources' "${MANIFEST}")"
build_root="$(jq -r '.defaults.roots.build' "${MANIFEST}")"
stage_root="$(jq -r '.defaults.roots.stage' "${MANIFEST}")"
packages_root="$(jq -r '.defaults.roots.packages' "${MANIFEST}")"

for path in "${sources_root}" "${build_root}" "${stage_root}" "${packages_root}"; do
  mkdir -p "${WORK_ROOT}/${path}"
done

component_count="$(jq '.components | length' "${MANIFEST}")"
ready_count="$(jq '[.components[] | select(.state == "ready")] | length' "${MANIFEST}")"
seed_count="$(jq '[.components[] | select(.state == "seed")] | length' "${MANIFEST}")"

{
  printf 'AuZiX source workbench boot\n'
  printf 'manifest=%s\n' "${MANIFEST}"
  printf 'origin=%s\n' "$(jq -r '.defaults.origin' "${MANIFEST}")"
  printf 'suite=%s\n' "$(jq -r '.defaults.suite' "${MANIFEST}")"
  printf 'architecture=%s\n' "$(jq -r '.defaults.architecture' "${MANIFEST}")"
  printf '\nroots:\n'
  printf '  sources=%s\n' "${sources_root}"
  printf '  build=%s\n' "${build_root}"
  printf '  stage=%s\n' "${stage_root}"
  printf '  packages=%s\n' "${packages_root}"
  printf '\ncomponents:\n'
  jq -r '.components[] | "  - \(.id) state=\(.state) source=\(.source.package) build=\(.build.system) prefix=\(.install.prefix)"' "${MANIFEST}"
} | tee "${plan_path}"

jq -n \
  --arg format "auzix-source-workbench-boot-v1" \
  --arg status "ready" \
  --arg manifest "${MANIFEST}" \
  --arg report_dir "${REPORT_DIR}" \
  --arg sources_root "${sources_root}" \
  --arg build_root "${build_root}" \
  --arg stage_root "${stage_root}" \
  --arg packages_root "${packages_root}" \
  --argjson components "${component_count}" \
  --argjson ready "${ready_count}" \
  --argjson seed "${seed_count}" \
  '{
    format: $format,
    status: $status,
    manifest: $manifest,
    report_dir: $report_dir,
    roots: {
      sources: $sources_root,
      build: $build_root,
      stage: $stage_root,
      packages: $packages_root
    },
    components: $components,
    ready: $ready,
    seed: $seed
  }' > "${summary_path}"

log "summary: ${summary_path}"
log "plan: ${plan_path}"
log "boot complete"
