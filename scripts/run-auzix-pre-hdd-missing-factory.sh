#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="${1:-$(date -u +%Y%m%dT%H%M%SZ)}"
BUILD_ROOT="${AUZIX_BUILD_ROOT:-/var/lib/auzix-build}"
WORK="${BUILD_ROOT}/factory-delta/${RUN_ID}"
SEED_ROOT="${AUZIX_FACTORY_SEED_ROOT:-${BUILD_ROOT}/iso-audit/current-root}"
REPOSITORY_INDEX="${AUZIX_FACTORY_REPOSITORY_INDEX:-${BUILD_ROOT}/pre-hdd-apk/20260830-r37/repository/x86_64/APKINDEX.tar.gz}"
ARCHIVE_PROFILE="${AUZIX_FACTORY_ARCHIVE_PROFILE:-${ROOT_DIR}/packaging/archive-profiles/pre-hdd-missing.json}"
MIDORI_ARCHIVE="${AUZIX_FACTORY_MIDORI_ARCHIVE:-${BUILD_ROOT}/source-current/out/auzix-packages/midori/midori-11.8.linux-x86_64.tar.xz}"
RESUME_SPOOL="${AUZIX_FACTORY_RESUME_SPOOL:-}"
FORCE_PACKAGES="${AUZIX_FACTORY_FORCE_PACKAGES:-}"
INPUT_LIST="${AUZIX_FACTORY_INPUT_LIST:-}"
IMAGE="auzix/extended-builder:${RUN_ID}"
CONTAINER="auzix-${RUN_ID}"

log() { printf '[pre-hdd-missing-factory] %s\n' "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

for command_name in awk docker find jq mount sort tar umount; do
  command -v "${command_name}" >/dev/null 2>&1 || die "missing command: ${command_name}"
done
[[ -s "${REPOSITORY_INDEX}" ]] || die "repository index not found: ${REPOSITORY_INDEX}"
[[ -s "${ARCHIVE_PROFILE}" ]] || die "archive profile not found: ${ARCHIVE_PROFILE}"
[[ -s "${SEED_ROOT}/System/Libraries/Runtime/glibc/libc.so.6" ]] ||
  die "validated seed root has no core glibc: ${SEED_ROOT}"

mkdir -p "${WORK}"/{logs,overlay-upper,overlay-work,root,spool}
[[ ! -e "${WORK}/run.status" ]] || die "run already has terminal status: ${WORK}/run.status"
if [[ -n "${RESUME_SPOOL}" ]]; then
  [[ -d "${RESUME_SPOOL}/entries" && -d "${RESUME_SPOOL}/packages" ]] ||
    die "resume spool is incomplete: ${RESUME_SPOOL}"
  cp -a "${RESUME_SPOOL}/entries" "${RESUME_SPOOL}/packages" "${WORK}/spool/"
fi

jq -r '.packages[]' "${ARCHIVE_PROFILE}" >"${WORK}/requested.packages"
jq -r '.package_names as $names | .packages[] | $names[.] // error("missing package_names mapping for " + .)' \
  "${ARCHIVE_PROFILE}" >"${WORK}/requested.repository-packages"
tar -xOzf "${REPOSITORY_INDEX}" APKINDEX | awk -F: '$1 == "P" {print $2}' | sort -u \
  >"${WORK}/repository.packages"

# This factory refreshes every package selected by the lifecycle profile.  The
# base repository may contain older copies, but their presence must not suppress
# regeneration.  Resume is identity-based against the supplied spool instead.
cp "${WORK}/requested.packages" "${WORK}/missing.packages"
jq -r '.package_names as $names | .packages[] | $names[.] | select(startswith("auzix-") | not)' \
  "${ARCHIVE_PROFILE}" >"${WORK}/missing.debian-packages"
if [[ -n "${INPUT_LIST}" ]]; then
  [[ -s "${INPUT_LIST}" ]] || die "explicit factory input list not found: ${INPUT_LIST}"
  awk 'NF && $1 !~ /^#/ {print $1}' "${INPUT_LIST}" >>"${WORK}/missing.debian-packages"
fi
for forced_package in ${FORCE_PACKAGES}; do
  [[ "${forced_package}" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] ||
    die "invalid forced Debian package: ${forced_package}"
  printf '%s\n' "${forced_package}" >>"${WORK}/missing.debian-packages"
done
sort -u -o "${WORK}/missing.debian-packages" "${WORK}/missing.debian-packages"
if jq -e '.packages | index("Midori") != null' "${ARCHIVE_PROFILE}" >/dev/null; then
  [[ -s "${MIDORI_ARCHIVE}" ]] || die "cached Midori archive not found: ${MIDORI_ARCHIVE}"
  printf 'midori\n' >"${WORK}/missing.native-packages"
else
  : >"${WORK}/missing.native-packages"
fi

log "run_id=${RUN_ID} refresh=$(wc -l <"${WORK}/requested.packages") repository=$(wc -l <"${WORK}/repository.packages") donors=$(wc -l <"${WORK}/missing.debian-packages") explicit_input=${INPUT_LIST:-none} forced=${FORCE_PACKAGES:-none}"
sed 's/^/[pre-hdd-missing-factory] queue=/' "${WORK}/missing.packages"
sed 's/^/[pre-hdd-missing-factory] donor=/' "${WORK}/missing.debian-packages"

run_complete=0
cleanup() {
  rc=$?
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
  if mountpoint -q "${WORK}/root"; then
    umount "${WORK}/root" || true
  fi
  if [[ "${run_complete}" != "1" && ! -e "${WORK}/run.status" ]]; then
    printf 'failed rc=%s\n' "${rc}" >"${WORK}/run.status"
  fi
}
trap cleanup EXIT INT TERM

mount -t overlay overlay \
  -o "lowerdir=${SEED_ROOT},upperdir=${WORK}/overlay-upper,workdir=${WORK}/overlay-work" \
  "${WORK}/root"

docker build --pull=false -t "${IMAGE}" -f "${ROOT_DIR}/docker/extended-builder/Dockerfile" "${ROOT_DIR}"
docker run --name "${CONTAINER}" \
  -v "${ROOT_DIR}:/workspace" \
  -v "${WORK}/root:/factory-root" \
  -v "${WORK}/spool:/factory-spool" \
  -v "${WORK}/missing.debian-packages:/factory-input/missing.packages:ro" \
  -v "${WORK}/missing.native-packages:/factory-input/native.packages:ro" \
  -v "${MIDORI_ARCHIVE}:/factory-input/midori.tar.xz:ro" \
  -e AUZIX_PACKAGE_SPOOL_DIR=/factory-spool \
  -e AUZIX_TRIXIE_REPORT="${RUN_ID}.report.json" \
  -e AUZIX_TRIXIE_BUILD_DEPENDS=1 \
  -e AUZIX_TRIXIE_INCLUDE_RECOMMENDS=0 \
  -e AUZIX_TRIXIE_RESUME_BY_SPOOL=1 \
  -e AUZIX_TRIXIE_OVERWRITE_NATIVE=1 \
  -e AUZIX_MIDORI_ARCHIVE=/factory-input/midori.tar.xz \
  "${IMAGE}" bash -lc '
    set -euo pipefail
    apt-get update
    ./scripts/run-auzix-trixie-intake.sh /factory-input/missing.packages /factory-root
    if grep -Fxq midori /factory-input/native.packages &&
       ! find /factory-spool/entries -maxdepth 1 -name "Midori-*.json" -print -quit | grep -q .; then
      ./scripts/build-auzix-midori-package.sh /factory-root
      midori_receipt="$(find /factory-root/System/PackageDB -maxdepth 1 -name "Midori-*.auzix.json" -print -quit)"
      test -n "${midori_receipt}"
      ./scripts/package-auzix-receipt-archive.sh /factory-root "${midori_receipt}" /factory-spool
    fi
    cp "out/package-bot/'"${RUN_ID}"'.report.json" /factory-spool/
  ' 2>&1 | tee "${WORK}/logs/factory.log"

printf 'complete\n' >"${WORK}/run.status"
run_complete=1
log "complete spool_entries=$(find "${WORK}/spool/entries" -maxdepth 1 -type f 2>/dev/null | wc -l) work=${WORK}"
