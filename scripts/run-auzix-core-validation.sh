#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${AUZIX_ROOT:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
REPORT_DIR="${AUZIX_CORE_REPORT_DIR:-${ROOT_DIR}/out/core-validation}"
BUILD_ROOT="${AUZIX_CORE_BUILD:-1}"
RUN_CONTAINER="${AUZIX_CORE_CONTAINER:-1}"
IMAGE_NAME="${AUZIX_STRICT_IMAGE:-auzix-strict:core-validation}"

mkdir -p "${REPORT_DIR}"

summary_path="${REPORT_DIR}/summary.json"
prompt_path="${REPORT_DIR}/ollama-prompt.md"
build_log="${REPORT_DIR}/build.log"
audit_report="${REPORT_DIR}/strict-root-audit.txt"
audit_stdout="${REPORT_DIR}/strict-root-audit.stdout"
runtime_report="${REPORT_DIR}/package-runtime-audit.txt"
container_report="${REPORT_DIR}/container-smoke.txt"

status="pass"
failures=0

log() {
  printf '[auzix-core-validation] %s\n' "$*" | tee -a "${REPORT_DIR}/runner.log"
}

record_failure() {
  status="fail"
  failures=$((failures + 1))
  log "FAIL: $*"
}

run_step() {
  local name="$1"
  local output="$2"
  shift 2
  log "running ${name}"
  if "$@" >"${output}" 2>&1; then
    log "complete ${name}"
    return 0
  fi
  record_failure "${name}; see ${output}"
  return 1
}

if [[ "${BUILD_ROOT}" == "1" ]]; then
  run_step "strict root build" "${build_log}" \
    make \
      auzix-strict-root \
      auzix-strict-busybox \
      auzix-strict-live-tools \
      auzix-strict-access \
      auzix-strict-package-tools \
      auzix-strict-installer \
      auzix-strict-installer-test \
      auzix-strict-dbus \
      auzix-strict-udev \
      auzix-strict-acpid \
      auzix-strict-pulseaudio \
      auzix-strict-strace \
      auzix-strict-host-xorg \
      auzix-strict-host-e \
      auzix-strict-host-terminology \
      auzix-strict-host-xterm \
      auzix-strict-lightdm \
      auzix-strict-display-templates \
      auzix-strict-user-defaults \
      auzix-strict-grub || true
else
  log "skipping build because AUZIX_CORE_BUILD=${BUILD_ROOT}"
fi

run_step "strict root audit" "${audit_stdout}" \
  "${ROOT_DIR}/scripts/audit-auzix-strict-root.sh" "${AUZIX_ROOT}" "${audit_report}" || true

run_step "package runtime audit" "${runtime_report}" \
  "${ROOT_DIR}/scripts/audit-auzix-package-runtime.sh" "${AUZIX_ROOT}" || true

if [[ "${RUN_CONTAINER}" == "1" ]]; then
  run_step "strict container import" "${container_report}" \
    env AUZIX_STRICT_IMAGE="${IMAGE_NAME}" "${ROOT_DIR}/scripts/build-auzix-strict-container.sh" || true

  if docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    {
      printf 'container=%s\n' "${IMAGE_NAME}"
      docker run --rm "${IMAGE_NAME}" /Programs/BusyBox/1.36.1/Commands/busybox sh -c '
        set -e
        test -x /Programs/BusyBox/1.36.1/Commands/busybox
        test -x /System/Tools/start-enlightenment-session
        test -e /System/Tools/launch-auzix-installer
        test -s /Users/auzix/.config/autostart/auzix-installer.desktop
        test -s /System/Settings/installer/questions.json
        test -d /proc
        test -d /dev
        echo core-container-smoke-ok
      '
    } >>"${container_report}" 2>&1 || record_failure "container smoke; see ${container_report}"
  else
    record_failure "container image was not created: ${IMAGE_NAME}"
  fi
else
  printf 'container-smoke-skipped AUZIX_CORE_CONTAINER=%s\n' "${RUN_CONTAINER}" >"${container_report}"
  log "skipping container smoke because AUZIX_CORE_CONTAINER=${RUN_CONTAINER}"
fi

strict_fail_count="$(grep -c '^FAIL:' "${audit_report}" 2>/dev/null || true)"
runtime_fail_count="$(grep -c '^FAIL:' "${runtime_report}" 2>/dev/null || true)"
warn_count="$(grep -h '^WARN:' "${audit_report}" "${runtime_report}" 2>/dev/null | wc -l | tr -d ' ')"
receipt_count="$(find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name '*.auzix.json' 2>/dev/null | wc -l | tr -d ' ')"
executable_count="$(find "${AUZIX_ROOT}/Programs" "${AUZIX_ROOT}/System/Tools" -type f -perm /111 2>/dev/null | wc -l | tr -d ' ')"

if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg status "${status}" \
    --arg root "${AUZIX_ROOT}" \
    --arg report_dir "${REPORT_DIR}" \
    --arg image "${IMAGE_NAME}" \
    --argjson failures "${failures}" \
    --argjson strict_failures "${strict_fail_count:-0}" \
    --argjson runtime_failures "${runtime_fail_count:-0}" \
    --argjson warnings "${warn_count:-0}" \
    --argjson receipts "${receipt_count:-0}" \
    --argjson executables "${executable_count:-0}" \
    '{
      format: "auzix-core-validation-report-v1",
      status: $status,
      failures: $failures,
      strict_root_failures: $strict_failures,
      package_runtime_failures: $runtime_failures,
      warnings: $warnings,
      package_receipts: $receipts,
      executables: $executables,
      root: $root,
      container_image: $image,
      report_dir: $report_dir
    }' > "${summary_path}"
else
  cat >"${summary_path}" <<JSON
{"format":"auzix-core-validation-report-v1","status":"${status}","failures":${failures},"root":"${AUZIX_ROOT}","container_image":"${IMAGE_NAME}","report_dir":"${REPORT_DIR}"}
JSON
fi

{
  printf '# AuZiX Core Validation Triage Prompt\n\n'
  printf 'You are reviewing a bounded AuZiX core-root validation run. Focus on root OS invariants before ISO, VM, browser, or GUI polish.\n\n'
  printf '## Summary\n\n'
  cat "${summary_path}"
  printf '\n\n## Priority\n\n'
  printf '1. Explain any FAIL lines from strict-root or package-runtime audits.\n'
  printf '2. Identify package-owned fixes before boot-script repair fixes.\n'
  printf '3. Call out legacy /usr, /lib, /etc, /var, /tmp assumptions that should be receipts, wrappers, or compatibility exports.\n'
  printf '4. Keep suggestions small enough for one BKC pipeline iteration.\n\n'
  printf '## Strict Root Failures\n\n'
  grep '^FAIL:' "${audit_report}" 2>/dev/null || printf 'No strict-root FAIL lines.\n'
  printf '\n## Package Runtime Failures\n\n'
  grep '^FAIL:' "${runtime_report}" 2>/dev/null || printf 'No package-runtime FAIL lines.\n'
  printf '\n## Container Smoke Tail\n\n'
  tail -40 "${container_report}" 2>/dev/null || true
} > "${prompt_path}"

log "summary: ${summary_path}"
log "prompt: ${prompt_path}"

if [[ "${status}" == "pass" ]]; then
  log "core validation passed"
  exit 0
fi

log "core validation failed with ${failures} failed step(s)"
exit 1
