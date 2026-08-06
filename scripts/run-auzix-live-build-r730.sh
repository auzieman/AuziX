#!/usr/bin/env bash
set -euo pipefail

# Run this on r730-ai-01. NS1 NFS is the source-of-truth and publication
# surface, not the build disk. Each run gets a disposable local snapshot on
# the worker so package expansion and SquashFS writes use the worker's disk.

SOURCE_ROOT="${AUZIX_SOURCE_ROOT:-/mnt/ns1/AuziX/src}"
RECEIPT_DIR="${AUZIX_RECEIPT_DIR:-/mnt/ns1/AuziX/build-receipts}"
KEY_FILE="${AUZIX_AUTHORIZED_KEYS_FILE:-/mnt/ns1/AuziX/runtime/keys/authorized_keys}"
ACCESS_PROFILE="${AUZIX_ACCESS_PROFILE:-lab-password}"
ROOT_PASSWORD_HASH_FILE="${AUZIX_ROOT_PASSWORD_HASH_FILE:-/mnt/ns1/AuziX/runtime/secrets/live-root-shadow}"
BUILDER_IMAGE="${AUZIX_BUILDER_IMAGE:-auzix/builder:lab}"
ISO_NAME="${AUZIX_ISO_NAME:-auzix-live-efl-candidate.iso}"
RUN_ID="${AUZIX_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN_NAME="auzix-live-build-${RUN_ID}"
WORK_ROOT="${AUZIX_WORK_ROOT:-/var/lib/auzix-build}"
PUBLISH_DIR="${AUZIX_PUBLISH_DIR:-${SOURCE_ROOT}/artifacts/auzix}"

fail() { printf '[auzix-r730-build] FAIL: %s\n' "$*" >&2; exit 1; }
log() { printf '[auzix-r730-build] %s\n' "$*"; }

[[ -d "${SOURCE_ROOT}" ]] || fail "source root is missing: ${SOURCE_ROOT}"
[[ -s "${KEY_FILE}" ]] || fail "runtime authorized_keys input is missing: ${KEY_FILE}"
if [[ "${ACCESS_PROFILE}" == "lab-password" ]]; then
  [[ -s "${ROOT_PASSWORD_HASH_FILE}" ]] || fail "runtime root password hash is missing: ${ROOT_PASSWORD_HASH_FILE}"
fi
command -v docker >/dev/null || fail 'docker is required on the worker'
mkdir -p "${RECEIPT_DIR}"

receipt="${RECEIPT_DIR}/live-build-${RUN_ID}.receipt"
log_file="${RECEIPT_DIR}/live-build-${RUN_ID}.log"
work_dir="${WORK_ROOT}/runs/${RUN_ID}"
work_source="${work_dir}/src"
work_log="${work_dir}/live-build.log"
work_receipt="${work_dir}/live-build.receipt"
work_iso="${work_source}/artifacts/auzix/${ISO_NAME}"
iso_path="${PUBLISH_DIR}/${ISO_NAME}"

publish_metadata() {
  cp "${work_receipt}" "${receipt}"
  cp "${work_log}" "${log_file}" 2>/dev/null || true
}

on_exit() {
  local status=$?
  if [[ ${status} -ne 0 && -f "${work_receipt}" ]]; then
    printf 'finished_at=%s\nstatus=fail\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${work_receipt}"
    publish_metadata
  fi
  exit "${status}"
}
trap on_exit EXIT

# Publish the active run before the expensive work begins.  Consumers use this
# pointer only as a convenience; the receipt remains the source of truth.
printf '%s\n' "${RUN_ID}" > "${RECEIPT_DIR}/live-build-current.run"

rm -rf "${work_dir}"
mkdir -p "${work_source}"
log "syncing clean source snapshot to local worker disk"
# The worker deliberately stays lean. Use the builder container as the short
# transfer job: NFS is read-only input, the worker directory is writable
# scratch, and no small-file build traffic returns to NFS.
docker run --rm \
  -v "${SOURCE_ROOT}:/source:ro" \
  -v "${work_dir}:/work" \
  "${BUILDER_IMAGE}" \
  rsync -a --delete \
    --exclude '.git/' \
    --exclude 'out/' \
    --exclude 'artifacts/' \
    --exclude 'downloads/' \
    /source/ /work/src/

cat >"${work_receipt}" <<EOF
format=auzix-live-build-receipt-v1
run_id=${RUN_ID}
worker=r730-ai-01
source_root=${SOURCE_ROOT}
worker_snapshot=${work_source}
builder_image=${BUILDER_IMAGE}
iso_name=${ISO_NAME}
authorized_keys=runtime-mounted-public-key
access_profile=${ACCESS_PROFILE}
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
publish_metadata

log "building ${BUILDER_IMAGE}"
docker build -t "${BUILDER_IMAGE}" -f "${work_source}/docker/builder/Dockerfile" "${work_source}" 2>&1 | tee -a "${work_log}"

log "building standard live media: ${ISO_NAME}"
docker run --rm --name "${RUN_NAME}" \
  -v "${work_source}:/workspace" \
  -v "${KEY_FILE}:/run/auzix-runtime/authorized_keys:ro" \
  -v "${ROOT_PASSWORD_HASH_FILE}:/run/auzix-runtime/live-root-shadow:ro" \
  -w /workspace \
  -e AUZIX_ROOT_SOURCE=/workspace/out/auzix-strict/AuzixRoot \
  -e AUZIX_AUTHORIZED_KEYS_SOURCE=/run/auzix-runtime/authorized_keys \
  -e AUZIX_ACCESS_PROFILE="${ACCESS_PROFILE}" \
  -e AUZIX_ROOT_PASSWORD_HASH_FILE=/run/auzix-runtime/live-root-shadow \
  -e AUZIX_ISO_NAME="${ISO_NAME}" \
  "${BUILDER_IMAGE}" \
  ./scripts/build-auzix-strict-all.sh 2>&1 | tee -a "${work_log}"

[[ -s "${work_iso}" ]] || fail "expected ISO is missing: ${work_iso}"
docker run --rm \
  -v "${work_source}:/workspace:ro" \
  -w /workspace \
  -e AUZIX_REQUIRE_UEFI=1 \
  "${BUILDER_IMAGE}" \
  ./scripts/validate-auzix-boot-iso.sh "/workspace/artifacts/auzix/${ISO_NAME}" 2>&1 | tee -a "${work_log}"

sha256sum "${work_iso}" | tee "${work_iso}.sha256" | tee -a "${work_log}"
install -d "${PUBLISH_DIR}"
rsync -a "${work_iso}" "${work_iso}.sha256" "${PUBLISH_DIR}/"
printf 'finished_at=%s\niso_path=%s\nsha256_file=%s\nstatus=pass\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${iso_path}" "${iso_path}.sha256" >>"${work_receipt}"
publish_metadata
trap - EXIT
log "PASS run_id=${RUN_ID} receipt=${receipt}"
