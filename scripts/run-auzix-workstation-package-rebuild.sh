#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${AUZIX_ROOT:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
REPORT_DIR="${AUZIX_REPORT_DIR:-${ROOT_DIR}/out/package-rebuild}"
RUN_ID="${AUZIX_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
LOG_FILE="${REPORT_DIR}/workstation-package-rebuild-${RUN_ID}.log"
SUMMARY_FILE="${REPORT_DIR}/workstation-package-rebuild-${RUN_ID}.summary"

mkdir -p "${REPORT_DIR}"

log() {
  printf '[auzix-workstation-rebuild] %s\n' "$*" | tee -a "${LOG_FILE}"
}

run_step() {
  log "STEP: $*"
  "$@" 2>&1 | tee -a "${LOG_FILE}"
}

cd "${ROOT_DIR}"

cat >"${SUMMARY_FILE}" <<EOF
format=auzix-workstation-package-rebuild-v1
run_id=${RUN_ID}
auzix_root=${AUZIX_ROOT}
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

log "using AUZIX_ROOT=${AUZIX_ROOT}"
log "normalizing package owners is disabled unless explicitly requested"
export AUZIX_PACKAGE_NORMALIZE_OWNERS="${AUZIX_PACKAGE_NORMALIZE_OWNERS:-0}"
export AUZIX_PUBLISH_UNVALIDATED_DESKTOP_ENTRIES="${AUZIX_PUBLISH_UNVALIDATED_DESKTOP_ENTRIES:-0}"

# Core and service spine. These are native AUZiX package builders and must run
# before Debian intake so wrappers and package installation have a sane base.
run_step make auzix-strict-root
run_step make auzix-strict-probe
run_step make auzix-strict-dynprobe
run_step make auzix-strict-busybox
run_step make auzix-strict-access
run_step make auzix-strict-service-runtime
run_step make auzix-strict-package-tools
run_step make auzix-strict-dbus
run_step make auzix-strict-udev
run_step make auzix-strict-acpid
run_step make auzix-strict-sudo
run_step make auzix-strict-userspace-tools

# Targeted first: rebuild the packages we know VM135 exposed as broken/stale.
run_step env \
  AUZIX_TRIXIE_REPORT="userspace-repair-${RUN_ID}.json" \
  ./scripts/run-auzix-trixie-intake.sh \
  profiles/packages/auzix-2026-08-11-userspace-repair.packages \
  "${AUZIX_ROOT}"

# Then the broader Trixie mirror/app sweep. This should reuse already-good
# receipts and fill dependency gaps instead of hand-carrying one library at a
# time.
run_step env \
  AUZIX_TRIXIE_REPORT="trixie-user-apps-${RUN_ID}.json" \
  ./scripts/run-auzix-trixie-intake.sh \
  profiles/packages/auzix-trixie-user-apps.packages \
  "${AUZIX_ROOT}"

# AUZiX-native desktop surfaces and Flatpak adapters sit on top of the payloads.
run_step make auzix-strict-flatpak-runtime-support
run_step make auzix-strict-flatpak-runtime
run_step make auzix-strict-flatpak-adapters
run_step make auzix-strict-desktop-assets-package
run_step make auzix-strict-desktop-repo-packages
run_step make auzix-strict-desktop-integration
run_step make auzix-strict-display-templates
run_step make auzix-strict-user-defaults
run_step make auzix-strict-live-tools

# Finalize the staged root exactly as auzix-pkg install does after extraction.
if [[ -x "${AUZIX_ROOT}/System/Tools/finalize-installed-root" ]]; then
  run_step "${AUZIX_ROOT}/System/Tools/finalize-installed-root" "${AUZIX_ROOT}"
fi

run_step ./scripts/audit-auzix-package-runtime.sh "${AUZIX_ROOT}"
run_step make auzix-strict-package-repo

cat >>"${SUMMARY_FILE}" <<EOF
finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
status=pass
log=${LOG_FILE}
EOF

log "PASS summary=${SUMMARY_FILE}"
