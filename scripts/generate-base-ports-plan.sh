#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${1:-${ROOT_DIR}/packages/base-ports.manifest.json}"
OUT_DIR="${AUZIX_BASE_PORTS_OUT:-${ROOT_DIR}/out/source-workbench/base-ports}"
PLAN_PATH="${OUT_DIR}/base-ports-plan.txt"
REPORT_PATH="${OUT_DIR}/base-ports-report.json"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

require_cmd jq

mkdir -p "${OUT_DIR}"

jq -e '
  .format == "auzix-base-ports-v1" and
  .policy.shared_library_root == "/System/Libraries" and
  .policy.compatibility_roots_allowed == false
' "${MANIFEST}" >/dev/null

target_count="$(jq '[.phases[].targets[]] | length' "${MANIFEST}")"
phase_count="$(jq '.phases | length' "${MANIFEST}")"
compat_count="$(jq '[.. | strings | select(test("/System/Compatibility|/usr/lib/x86_64-linux-gnu|/lib64"))] | length' "${MANIFEST}")"

if [[ "${compat_count}" -ne 0 ]]; then
  printf 'Base ports manifest contains compatibility paths; count=%s\n' "${compat_count}" >&2
  exit 1
fi

{
  printf 'AuZiX base ports plan\n'
  printf 'manifest=%s\n' "${MANIFEST}"
  printf 'profile=%s\n' "$(jq -r '.profile' "${MANIFEST}")"
  printf 'shared_library_root=%s\n' "$(jq -r '.policy.shared_library_root' "${MANIFEST}")"
  printf 'phases=%s targets=%s\n\n' "${phase_count}" "${target_count}"
  jq -r '
    .phases[] |
    "## " + .id + "\n" +
    .purpose + "\n" +
    ((.targets // []) | map("  - " + .name + " source=" + .source.package + " prefix=" + .prefix + " promotes=" + ((.promotes // []) | join(","))) | join("\n")) +
    "\n"
  ' "${MANIFEST}"
} > "${PLAN_PATH}"

jq -n \
  --arg format "auzix-base-ports-report-v1" \
  --arg status "planned" \
  --arg manifest "${MANIFEST}" \
  --arg plan "${PLAN_PATH}" \
  --arg shared_library_root "/System/Libraries" \
  --argjson phases "${phase_count}" \
  --argjson targets "${target_count}" \
  --argjson compatibility_path_count "${compat_count}" \
  --slurpfile ports "${MANIFEST}" \
  '{
    format: $format,
    status: $status,
    manifest: $manifest,
    plan: $plan,
    shared_library_root: $shared_library_root,
    phase_count: $phases,
    target_count: $targets,
    compatibility_path_count: $compatibility_path_count,
    current_bridge_inherited_tools: [
      "/bin/bash",
      "/usr/bin/jq",
      "/usr/bin/lua5.4",
      "/usr/bin/luac5.4",
      "/etc/ssl/certs"
    ],
    replacement_targets: ($ports[0].phases | map(.targets[]) | map({name, prefix, commands, promotes})),
    next_gate: "Build phase 00-bootstrap-runtime into /Programs, rerun native container, and shrink current_bridge_inherited_tools."
  }' > "${REPORT_PATH}"

printf '[base-ports] plan: %s\n' "${PLAN_PATH}"
printf '[base-ports] report: %s\n' "${REPORT_PATH}"
