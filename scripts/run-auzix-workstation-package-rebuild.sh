#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${AUZIX_ROOT:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
REPORT_DIR="${AUZIX_REPORT_DIR:-${ROOT_DIR}/out/package-rebuild}"
RUN_ID="${AUZIX_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
export AUZIX_LOCKED_EXECUTION=1
REBASE_LOCK="${AUZIX_REBASE_LOCK:-}"
LOG_FILE="${REPORT_DIR}/workstation-package-rebuild-${RUN_ID}.log"
SUMMARY_FILE="${REPORT_DIR}/workstation-package-rebuild-${RUN_ID}.summary"
PACKAGE_SPOOL_DIR="${AUZIX_PACKAGE_SPOOL_DIR:-${ROOT_DIR}/artifacts/auzix/package-spool-${RUN_ID}}"
LOCK_DIR="$(cd "$(dirname "${REBASE_LOCK:-.}")" 2>/dev/null && pwd || true)"
LOCKED_SELECTION="${AUZIX_LOCKED_SELECTION:-${LOCK_DIR}/selected-current-head.tsv}"
LOCKED_PROFILE="${REPORT_DIR}/locked-intake-${RUN_ID}.packages"

mkdir -p "${REPORT_DIR}"

log() {
  printf '[auzix-workstation-rebuild] %s\n' "$*" | tee -a "${LOG_FILE}"
}

run_step() {
  log "STEP: $*"
  "$@" 2>&1 | tee -a "${LOG_FILE}"
}

quarantine_alt_glibc_receipts() {
  local quarantine_dir="${REPORT_DIR}/quarantine-alt-glibc-${RUN_ID}"
  local count=0
  mkdir -p "${quarantine_dir}/System/PackageDB"
  while IFS= read -r receipt; do
    [[ -s "${receipt}" ]] || continue
    if grep -F '/Programs/Libc6/current' "${receipt}" >/dev/null 2>&1; then
      name="$(jq -r '.name // empty' "${receipt}" 2>/dev/null || true)"
      version="$(jq -r '.version // empty' "${receipt}" 2>/dev/null || true)"
      prefix="$(jq -r '.prefix // .paths.prefix // empty' "${receipt}" 2>/dev/null || true)"
      log "QUARANTINE alt-glibc receipt name=${name:-unknown} version=${version:-unknown} receipt=${receipt#${AUZIX_ROOT}/}"
      mv -f "${receipt}" "${quarantine_dir}/System/PackageDB/"
      if [[ -n "${prefix}" && "${prefix}" == /Programs/* && -e "${AUZIX_ROOT}${prefix}" ]]; then
        mkdir -p "${quarantine_dir}/Programs/${name:-unknown}"
        mv -f "${AUZIX_ROOT}${prefix}" "${quarantine_dir}/Programs/${name:-unknown}/" 2>/dev/null || true
      fi
      count=$((count + 1))
    fi
  done < <(find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f -name '*.json' -print | sort)
  log "QUARANTINE_DONE alt_glibc_receipts=${count} path=${quarantine_dir}"
}

cd "${ROOT_DIR}"

if [[ -z "${REBASE_LOCK}" ]]; then
  log "STOP: workstation rebuild is disabled after the substrate rebase boundary."
  log "Run scripts/plan-auzix-native-rebase.sh first and pass AUZIX_REBASE_LOCK=/path/to/build-tree.lock.json."
  exit 2
fi

if [[ ! -s "${REBASE_LOCK}" ]]; then
  log "STOP: AUZIX_REBASE_LOCK does not exist: ${REBASE_LOCK}"
  exit 2
fi

jq -e '
  .format == "auzix-native-rebase-lock-v1" and
  (.status | test("^locked")) and
  (.manifest_lock_sha256 | type == "string" and length > 0)
' "${REBASE_LOCK}" >/dev/null || {
  log "STOP: invalid native rebase lock: ${REBASE_LOCK}"
  exit 2
}

log "using native rebase lock=${REBASE_LOCK}"

if [[ ! -s "${LOCKED_SELECTION}" ]]; then
  log "STOP: locked package selection does not exist: ${LOCKED_SELECTION}"
  exit 2
fi

awk -F '\t' 'NR > 1 && $3 == "selected" {print $1}' "${LOCKED_SELECTION}" >"${LOCKED_PROFILE}"
locked_package_count="$(wc -l <"${LOCKED_PROFILE}" | tr -d ' ')"
if [[ "${locked_package_count}" -eq 0 ]]; then
  log "STOP: locked package selection is empty: ${LOCKED_SELECTION}"
  exit 2
fi
log "locked package transaction count=${locked_package_count} source=${LOCKED_SELECTION}"

cat >"${SUMMARY_FILE}" <<EOF
format=auzix-workstation-package-rebuild-v1
run_id=${RUN_ID}
auzix_root=${AUZIX_ROOT}
rebase_lock=${REBASE_LOCK}
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

log "using AUZIX_ROOT=${AUZIX_ROOT}"
log "normalizing package owners is disabled unless explicitly requested"
export AUZIX_PACKAGE_NORMALIZE_OWNERS="${AUZIX_PACKAGE_NORMALIZE_OWNERS:-0}"
export AUZIX_PUBLISH_UNVALIDATED_DESKTOP_ENTRIES="${AUZIX_PUBLISH_UNVALIDATED_DESKTOP_ENTRIES:-0}"
export AUZIX_REPO_REJECT_ALT_GLIBC="${AUZIX_REPO_REJECT_ALT_GLIBC:-1}"
export AUZIX_DEBIAN_SUITE="${AUZIX_DEBIAN_SUITE:-trixie}"
export AUZIX_STRICT_RELEASE_LANE="${AUZIX_STRICT_RELEASE_LANE:-1}"
export AUZIX_PACKAGE_SPOOL_DIR="${PACKAGE_SPOOL_DIR}"
mkdir -p "${AUZIX_PACKAGE_SPOOL_DIR}/packages" "${AUZIX_PACKAGE_SPOOL_DIR}/entries"
log "using AUZIX_PACKAGE_SPOOL_DIR=${AUZIX_PACKAGE_SPOOL_DIR}"

quarantine_alt_glibc_receipts
run_step ./scripts/preflight-auzix-release-lane.sh \
  --root "${AUZIX_ROOT}" \
  --suite "${AUZIX_DEBIAN_SUITE}" \
  --lint-recipes "${ROOT_DIR}/packages"

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

# Consume the committed package transaction exactly once. Dependency discovery
# happened in the planner and is forbidden here: execution must never expand
# or reorder the locked universe while mutating the target root.
run_step env \
  AUZIX_TRIXIE_BUILD_DEPENDS=0 \
  AUZIX_TRIXIE_REPORT="locked-intake-${RUN_ID}.json" \
  ./scripts/run-auzix-trixie-intake.sh \
  "${LOCKED_PROFILE}" \
  "${AUZIX_ROOT}"

# AUZiX-native desktop surfaces and Flatpak adapters sit on top of the payloads.
run_step make auzix-strict-flatpak-runtime-support
run_step make auzix-strict-flatpak-runtime
run_step make auzix-strict-flatpak-adapters
run_step make auzix-strict-e-assets
run_step make auzix-strict-desktop-assets-package
run_step make auzix-strict-desktop-repo-packages
run_step make auzix-strict-desktop-integration
run_step make auzix-strict-display-templates
run_step make auzix-strict-user-defaults
run_step make auzix-strict-live-tools

# Finalize the staged root exactly as auzix-pkg install does after extraction.
if [[ -x "${AUZIX_ROOT}/System/Tools/finalize-installed-root" ]]; then
  if "${AUZIX_ROOT}/System/Tools/finalize-installed-root" "${AUZIX_ROOT}" >>"${LOG_FILE}" 2>&1; then
    log "finalized installed root via host namespace"
  else
    log "host namespace finalizer failed; retrying inside AUZiX root"
    run_step chroot "${AUZIX_ROOT}" /System/Tools/finalize-installed-root /
  fi
fi

run_step ./scripts/audit-auzix-package-runtime.sh "${AUZIX_ROOT}"
run_step make auzix-strict-package-repo

cat >>"${SUMMARY_FILE}" <<EOF
finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
status=pass
log=${LOG_FILE}
EOF

log "PASS summary=${SUMMARY_FILE}"
