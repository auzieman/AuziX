#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLICE="${1:-filesystem-tools}"
OLLAMA_URL="${AUZIX_OLLAMA_URL:-http://192.168.1.9:11434}"
OLLAMA_MODEL="${AUZIX_OLLAMA_MODEL:-qwen3.5:latest}"
REPORT_DIR="${ROOT_DIR}/out/source-workbench/extended-ports"
LOG_PATH="${REPORT_DIR}/${SLICE}.build.log"
FAILURE_DIR="${REPORT_DIR}/failures"

mkdir -p "${REPORT_DIR}" "${FAILURE_DIR}"

case "${SLICE}" in
  filesystem-tools)
    service=extended-filesystem-builder
    target=E2fsprogs-Dosfstools
    ;;
  *)
    printf 'Unknown extended-port slice: %s\n' "${SLICE}" >&2
    exit 2
    ;;
esac

set +e
docker compose --profile extended-build up --build --abort-on-container-exit \
  "${service}" 2>&1 | tee "${LOG_PATH}"
build_status="${PIPESTATUS[0]}"
set -e

if [[ "${build_status}" -eq 0 ]]; then
  printf '[extended-port] %s passed; log=%s\n' "${SLICE}" "${LOG_PATH}"
  exit 0
fi

failure_path="${FAILURE_DIR}/${SLICE}.json"
ollama_path="${FAILURE_DIR}/${SLICE}.ollama.json"
log_tail="$(tail -n 120 "${LOG_PATH}")"
jq -n \
  --arg format "auzix-port-failure-v1" \
  --arg target "${target}" \
  --arg command "docker compose ${service}" \
  --arg log_tail "${log_tail}" \
  --arg manifest "packages/extended-ports.manifest.json" \
  '{format: $format, target: $target, command: $command, manifest: $manifest,
    log_tail: $log_tail,
    requested_answer: ["finding", "smallest_contract_adjustment", "validation_command"]}' \
  >"${failure_path}"

prompt="$(jq -c '{instruction:"Return only a JSON object with finding, smallest_contract_adjustment, and validation_command. Prefer flags and environment changes; do not change unrelated packages or publish anything.", failure:.}' "${failure_path}")"
if jq -n --arg model "${OLLAMA_MODEL}" --arg prompt "${prompt}" \
    '{model:$model,prompt:$prompt,stream:false}' |
    curl -sS --fail --max-time 180 -H 'Content-Type: application/json' \
      -d @- "${OLLAMA_URL%/}/api/generate" >"${ollama_path}"; then
  printf '[extended-port] Ollama advice: %s\n' "${ollama_path}" >&2
else
  printf '[extended-port] Ollama unavailable; failure packet retained: %s\n' \
    "${failure_path}" >&2
fi

exit "${build_status}"
