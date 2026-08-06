#!/usr/bin/env bash
set -euo pipefail

# Config-only patcher for the known-working raw-root VM135 ISO.  It never
# rebuilds packages or the desktop: it copies the ISO, replaces only
# /AuzixRoot with a locally patched copy, and preserves the original boot map.
SOURCE_ROOT="${AUZIX_SOURCE_ROOT:-/mnt/ns1/AuziX/src}"
BASE_ISO="${AUZIX_BASE_ISO:-${SOURCE_ROOT}/artifacts/auzix/auzix-strict-desktop-vm134.iso}"
BASE_ROOT="${AUZIX_BASE_ROOT:-${SOURCE_ROOT}/out/auzix-iso/iso/AuzixRoot}"
KEY_FILE="${AUZIX_AUTHORIZED_KEYS_FILE:-/mnt/ns1/AuziX/runtime/keys/authorized_keys}"
ROOT_PASSWORD_HASH_FILE="${AUZIX_ROOT_PASSWORD_HASH_FILE:-/mnt/ns1/AuziX/runtime/secrets/live-root-shadow}"
PUBLISH_DIR="${AUZIX_PUBLISH_DIR:-${SOURCE_ROOT}/artifacts/auzix}"
WORK_ROOT="${AUZIX_WORK_ROOT:-/var/lib/auzix-build}"
RUN_ID="${AUZIX_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
ISO_NAME="${AUZIX_ISO_NAME:-auzix-vm135-access-${RUN_ID}.iso}"

fail() { printf '[auzix-raw-iso-access] FAIL: %s\n' "$*" >&2; exit 1; }
log() { printf '[auzix-raw-iso-access] %s\n' "$*"; }

[[ -f "${BASE_ISO}" ]] || fail "base ISO is missing: ${BASE_ISO}"
[[ -d "${BASE_ROOT}" ]] || fail "base root is missing: ${BASE_ROOT}"
[[ -s "${KEY_FILE}" ]] || fail "authorized keys input is missing"
[[ -s "${ROOT_PASSWORD_HASH_FILE}" ]] || fail "root password hash input is missing"
command -v docker >/dev/null || fail 'docker is required on R730'

work_dir="${WORK_ROOT}/raw-iso-access/${RUN_ID}"
work_root="${work_dir}/AuzixRoot"
iso_tree="${work_dir}/iso-tree"
candidate="${work_dir}/${ISO_NAME}"
log_file="${work_dir}/patch.log"
mkdir -p "${work_root}"

log 'copying the known root to local R730 scratch'
docker run --rm \
  -v "${BASE_ROOT}:/baseline:ro" -v "${work_dir}:/work" auzix/builder:lab \
  rsync -a --delete /baseline/ /work/AuzixRoot/

log 'applying live SSH key and password fallback configuration only'
docker run --rm \
  -v "${SOURCE_ROOT}:/source:ro" -v "${work_dir}:/work" \
  -v "${KEY_FILE}:/run/auzix-runtime/authorized_keys:ro" \
  -v "${ROOT_PASSWORD_HASH_FILE}:/run/auzix-runtime/live-root-shadow:ro" \
  auzix/builder:lab sh -ec '
    cp /source/scripts/stage-auzix-live-access.sh /work/stage-auzix-live-access.sh
    chmod 0755 /work/stage-auzix-live-access.sh
    AUZIX_ACCESS_PROFILE=lab-password \
    AUZIX_AUTHORIZED_KEYS_SOURCE=/run/auzix-runtime/authorized_keys \
    AUZIX_ROOT_PASSWORD_HASH_FILE=/run/auzix-runtime/live-root-shadow \
    /work/stage-auzix-live-access.sh /work/AuzixRoot
  '

log 'extracting the existing ISO tree and preserving its recorded boot specification'
mkdir -p "${iso_tree}"
docker run --rm \
  -v "$(dirname "${BASE_ISO}"):/isos:ro" -v "${work_dir}:/work" auzix/builder:lab \
  sh -ec "xorriso -osirrox on -indev /isos/$(basename "${BASE_ISO}") -extract / /work/iso-tree >/dev/null" \
  2>&1 | tee "${log_file}"
rm -rf "${iso_tree}/AuzixRoot"
mv "${work_root}" "${iso_tree}/AuzixRoot"

log 'rebuilding one ISO session from the original boot map and patched root only'
docker run --rm \
  -v "$(dirname "${BASE_ISO}"):/isos:ro" -v "${work_dir}:/work" auzix/builder:lab \
  sh -ec "xorriso -as mkisofs -V ISOIMAGE --grub2-mbr --interval:local_fs:0s-15s:zero_mbrpt,zero_gpt,zero_apm:/isos/$(basename "${BASE_ISO}") --protective-msdos-label -partition_cyl_align off -partition_offset 0 -partition_hd_cyl 117 -partition_sec_hd 32 -apm-block-size 2048 -hfsplus -efi-boot-part --efi-boot-image -c /boot.catalog -b /boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info -eltorito-alt-boot -e /efi.img -no-emul-boot -boot-load-size 5760 -o /work/${ISO_NAME} /work/iso-tree" \
  2>&1 | tee "${log_file}"

[[ -s "${candidate}" ]] || fail 'candidate ISO was not created'
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
docker run --rm -v "${work_dir}:/work:ro" -v "${tmp_dir}:/verify" auzix/builder:lab sh -ec '
  xorriso -osirrox on -indev "/work/'"${ISO_NAME}"'" -extract /AuzixRoot/System/Settings/ssh/sshd_config /verify/sshd_config >/dev/null
  xorriso -osirrox on -indev "/work/'"${ISO_NAME}"'" -extract /AuzixRoot/Users/root/.ssh/authorized_keys /verify/root_authorized_keys >/dev/null
  xorriso -osirrox on -indev "/work/'"${ISO_NAME}"'" -extract /AuzixRoot/Users/auzix/.ssh/authorized_keys /verify/auzix_authorized_keys >/dev/null
  grep -qx "PermitRootLogin yes" /verify/sshd_config
  grep -qx "PasswordAuthentication yes" /verify/sshd_config
  test -s /verify/root_authorized_keys
  test -s /verify/auzix_authorized_keys
  xorriso -indev "/work/'"${ISO_NAME}"'" -report_el_torito plain | tee /verify/eltorito.txt
  grep -q "BIOS" /verify/eltorito.txt
  grep -q "UEFI" /verify/eltorito.txt
' | tee -a "${log_file}"

sha256sum "${candidate}" | tee "${candidate}.sha256" | tee -a "${log_file}"
install -d "${PUBLISH_DIR}"
cp "${candidate}" "${candidate}.sha256" "${PUBLISH_DIR}/"
log "PASS: ${PUBLISH_DIR}/${ISO_NAME}"
