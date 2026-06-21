#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${1:-${ROOT_DIR}/packages/source-workbench.seed.json}"
WORK_ROOT="${AUZIX_WORKBENCH_ROOT:-${ROOT_DIR}}"
REPORT_DIR="${AUZIX_WORKBENCH_REPORT_DIR:-${WORK_ROOT}/out/source-workbench}"
TARGET_ROOT="${AUZIX_TARGET_ROOT:-${REPORT_DIR}/AuZiXTarget}"

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
target_report_path="${REPORT_DIR}/target-layout.txt"

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

mkdir -p \
  "${TARGET_ROOT}/System/S" \
  "${TARGET_ROOT}/System/PackageDB" \
  "${TARGET_ROOT}/System/Settings" \
  "${TARGET_ROOT}/System/State" \
  "${TARGET_ROOT}/System/Libraries" \
  "${TARGET_ROOT}/Programs" \
  "${TARGET_ROOT}/Services" \
  "${TARGET_ROOT}/Stacks" \
  "${TARGET_ROOT}/Work" \
  "${TARGET_ROOT}/Users" \
  "${TARGET_ROOT}/Volumes" \
  "${TARGET_ROOT}/Network"

cat > "${TARGET_ROOT}/System/S/system-startup.json" <<'JSON'
{
  "format": "auzix-system-startup-v1",
  "profile": "source-workbench-stage2",
  "phases": [
    {
      "id": "01-core-layout",
      "kind": "validate-paths",
      "required": ["/System", "/Programs", "/Work", "/Users", "/System/S"]
    },
    {
      "id": "02-package-startup",
      "kind": "include",
      "path": "/System/S/package-startup.json"
    },
    {
      "id": "03-graphical-deferred",
      "kind": "note",
      "message": "Graphical packages are added after the source workbench validates the core target."
    }
  ]
}
JSON

cat > "${TARGET_ROOT}/System/S/package-startup.json" <<'JSON'
{
  "format": "auzix-package-startup-v1",
  "profile": "source-workbench-stage2",
  "packages": []
}
JSON

cat > "${TARGET_ROOT}/System/S/system-startup.lua" <<'LUA'
#!/Programs/Lua/current/Commands/lua
local manifest = "/System/S/system-startup.json"
local log = "/System/State/source-workbench-startup.log"

local function append(line)
  local f = io.open(log, "a")
  if f then
    f:write(line .. "\n")
    f:close()
  end
  print(line)
end

append("auzix-stage2-startup manifest=" .. manifest)
append("core layout is staged; package and graphical startup remain data-driven")
LUA
chmod 0755 "${TARGET_ROOT}/System/S/system-startup.lua"

cat > "${TARGET_ROOT}/System/PackageDB/SourceWorkbench-stage2.auzix.json" <<JSON
{
  "name": "SourceWorkbench",
  "version": "stage2",
  "kind": "core",
  "prefix": "/System/S",
  "commands": ["/System/S/system-startup.lua"],
  "compatibility_exports": [],
  "notes": "Stage 2 target root created by the source workbench control-plane container."
}
JSON

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
  printf '  target=%s\n' "${TARGET_ROOT}"
  printf '\ncomponents:\n'
  jq -r '.components[] | "  - \(.id) state=\(.state) source=\(.source.package) build=\(.build.system) prefix=\(.install.prefix)"' "${MANIFEST}"
} | tee "${plan_path}"

{
  printf 'AuZiXTarget layout\n'
  printf 'target=%s\n' "${TARGET_ROOT}"
  find "${TARGET_ROOT}" -maxdepth 3 \( -type d -o -type f \) | sort
} > "${target_report_path}"

for required in \
  System/S/system-startup.json \
  System/S/package-startup.json \
  System/S/system-startup.lua \
  System/PackageDB/SourceWorkbench-stage2.auzix.json \
  Programs \
  Work \
  Users \
  Network; do
  if [[ ! -e "${TARGET_ROOT}/${required}" ]]; then
    printf 'Stage 2 target missing required path: /%s\n' "${required}" >&2
    exit 1
  fi
done

if command -v luac5.4 >/dev/null 2>&1; then
  luac5.4 -p "${TARGET_ROOT}/System/S/system-startup.lua"
elif command -v luac >/dev/null 2>&1; then
  luac -p "${TARGET_ROOT}/System/S/system-startup.lua"
else
  log "lua compiler not found; skipped startup Lua syntax check"
fi

jq -n \
  --arg format "auzix-source-workbench-boot-v1" \
  --arg status "ready" \
  --arg manifest "${MANIFEST}" \
  --arg report_dir "${REPORT_DIR}" \
  --arg target_root "${TARGET_ROOT}" \
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
    target_root: $target_root,
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
log "target: ${TARGET_ROOT}"
log "target report: ${target_report_path}"
log "boot complete"
