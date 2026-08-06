#!/usr/bin/env bash
set -euo pipefail

# Thin live-media assembler. It never runs the broad package build. The only
# mutable root is a local R730 copy of an explicitly named, known-good root.
SOURCE_ROOT="${AUZIX_SOURCE_ROOT:-/mnt/ns1/AuziX/src}"
BASELINE_ROOT="${AUZIX_BASELINE_ROOT:-${SOURCE_ROOT}/out/auzix-iso/iso/AuzixRoot}"
KEY_FILE="${AUZIX_AUTHORIZED_KEYS_FILE:-/mnt/ns1/AuziX/runtime/keys/authorized_keys}"
ROOT_PASSWORD_HASH_FILE="${AUZIX_ROOT_PASSWORD_HASH_FILE:-/mnt/ns1/AuziX/runtime/secrets/live-root-shadow}"
RECEIPT_DIR="${AUZIX_RECEIPT_DIR:-/mnt/ns1/AuziX/build-receipts}"
PUBLISH_DIR="${AUZIX_PUBLISH_DIR:-${SOURCE_ROOT}/artifacts/auzix}"
WORK_ROOT="${AUZIX_WORK_ROOT:-/var/lib/auzix-build}"
BUILDER_IMAGE="${AUZIX_BUILDER_IMAGE:-auzix/builder:lab}"
REFRESH_BUILDER="${AUZIX_REFRESH_BUILDER:-0}"
STAGE_LIVE_ACCESS="${AUZIX_STAGE_LIVE_ACCESS:-0}"
STAGE_EFL_INSTALLER="${AUZIX_STAGE_EFL_INSTALLER:-0}"
RUN_ID="${AUZIX_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
ISO_NAME="${AUZIX_ISO_NAME:-auzix-live-efl-baseline-${RUN_ID}.iso}"
RUN_NAME="auzix-live-assemble-${RUN_ID}"

fail() { printf '[auzix-r730-assemble] FAIL: %s\n' "$*" >&2; exit 1; }
log() { printf '[auzix-r730-assemble] %s\n' "$*"; }

[[ -d "${SOURCE_ROOT}" ]] || fail "source root missing: ${SOURCE_ROOT}"
[[ -d "${BASELINE_ROOT}" ]] || fail "baseline root missing: ${BASELINE_ROOT}"
if [[ "${STAGE_LIVE_ACCESS}" == "1" ]]; then
  [[ -s "${KEY_FILE}" ]] || fail "authorized keys input missing: ${KEY_FILE}"
  [[ -s "${ROOT_PASSWORD_HASH_FILE}" ]] || fail "root password hash input missing"
fi
command -v docker >/dev/null || fail 'docker is required on R730'

work_dir="${WORK_ROOT}/assemble/${RUN_ID}"
work_source="${work_dir}/src"
work_root="${work_dir}/AuzixRoot"
work_log="${work_dir}/assemble.log"
work_receipt="${work_dir}/assemble.receipt"
receipt="${RECEIPT_DIR}/live-assemble-${RUN_ID}.receipt"
log_file="${RECEIPT_DIR}/live-assemble-${RUN_ID}.log"
work_iso="${work_source}/artifacts/auzix/${ISO_NAME}"

publish_metadata() {
  install -d "${RECEIPT_DIR}"
  cp "${work_receipt}" "${receipt}" 2>/dev/null || true
  cp "${work_log}" "${log_file}" 2>/dev/null || true
}
on_exit() {
  status=$?
  if [[ ${status} -ne 0 ]]; then
    printf 'finished_at=%s\nstatus=fail\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"${work_receipt}" 2>/dev/null || true
    publish_metadata
  fi
  exit "${status}"
}
trap on_exit EXIT

rm -rf "${work_dir}"
mkdir -p "${work_source}" "${work_root}"
log 'snapshotting source and validated baseline to R730 local scratch'
docker run --rm \
  -v "${SOURCE_ROOT}:/source:ro" -v "${BASELINE_ROOT}:/baseline:ro" -v "${work_dir}:/work" \
  "${BUILDER_IMAGE}" sh -ec '
    rsync -a --delete --exclude .git/ --exclude out/ --exclude artifacts/ --exclude downloads/ /source/ /work/src/
    rsync -a --delete /baseline/ /work/AuzixRoot/
  '

cat >"${work_receipt}" <<EOF
format=auzix-live-assemble-receipt-v1
run_id=${RUN_ID}
worker=r730-ai-01
baseline_root=${BASELINE_ROOT}
worker_root=${work_root}
source_snapshot=${work_source}
deltas=approved-access-and-installer-only
iso_name=${ISO_NAME}
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
publish_metadata

if [[ "${REFRESH_BUILDER}" == "1" ]]; then
  log "refreshing disposable assembler image ${BUILDER_IMAGE}"
  docker build -t "${BUILDER_IMAGE}" -f "${work_source}/docker/builder/Dockerfile" "${work_source}" 2>&1 | tee -a "${work_log}"
else
  log "using existing assembler image ${BUILDER_IMAGE}; no builder refresh requested"
fi

log 'applying only approved deltas and assembling the ISO'
access_mount_args=()
if [[ "${STAGE_LIVE_ACCESS}" == "1" ]]; then
  access_mount_args+=(
    -v "${KEY_FILE}:/run/auzix-runtime/authorized_keys:ro"
    -v "${ROOT_PASSWORD_HASH_FILE}:/run/auzix-runtime/live-root-shadow:ro"
  )
fi
docker run --rm --name "${RUN_NAME}" \
  -v "${work_source}:/workspace" -v "${work_root}:/auzix-root" \
  "${access_mount_args[@]}" \
  -w /workspace \
  -e AUZIX_ROOT_SOURCE=/auzix-root \
  -e AUZIX_ISO_NAME="${ISO_NAME}" \
  -e AUZIX_STAGE_LIVE_ACCESS="${STAGE_LIVE_ACCESS}" \
  -e AUZIX_STAGE_EFL_INSTALLER="${STAGE_EFL_INSTALLER}" \
  -e AUZIX_ACCESS_PROFILE=lab-password \
  -e AUZIX_AUTHORIZED_KEYS_SOURCE=/run/auzix-runtime/authorized_keys \
  -e AUZIX_ROOT_PASSWORD_HASH_FILE=/run/auzix-runtime/live-root-shadow \
  "${BUILDER_IMAGE}" sh -ec '
    if [ "${AUZIX_STAGE_LIVE_ACCESS}" = 1 ]; then
      ./scripts/stage-auzix-live-access.sh /auzix-root
    fi
    if [ "${AUZIX_STAGE_EFL_INSTALLER}" = 1 ]; then
      ./scripts/build-auzix-installer-efl-package.sh /auzix-root
    fi
    # The selected baseline already owns the live desktop, session, and
    # service configuration.  Do not re-run its broad live-tools provisioner
    # here: alpha assembly is intentionally a thin consumer plus explicitly
    # approved deltas only.
    test -x /auzix-root/Services/ssh/run
    test -x /auzix-root/Programs/Midori/11.8/Commands/midori
    ./scripts/build-auzix-boot-iso.sh
  ' 2>&1 | tee -a "${work_log}"

[[ -s "${work_iso}" ]] || fail "ISO was not created: ${work_iso}"
docker run --rm -v "${work_source}:/workspace:ro" -w /workspace \
  "${BUILDER_IMAGE}" ./scripts/validate-auzix-boot-iso.sh "/workspace/artifacts/auzix/${ISO_NAME}" 2>&1 | tee -a "${work_log}"

sha256sum "${work_iso}" | tee "${work_iso}.sha256" | tee -a "${work_log}"
install -d "${PUBLISH_DIR}"
install -m 0644 "${work_iso}" "${work_iso}.sha256" "${PUBLISH_DIR}/"
printf 'finished_at=%s\nstatus=pass\niso_path=%s/%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${PUBLISH_DIR}" "${ISO_NAME}" >>"${work_receipt}"
publish_metadata
trap - EXIT
log "PASS run_id=${RUN_ID} iso=${PUBLISH_DIR}/${ISO_NAME}"
