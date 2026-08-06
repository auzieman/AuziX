#!/usr/bin/env bash
set -euo pipefail

# Build a bounded recovery derivative from the last runtime-proven ISO. The
# embedded SquashFS is the only root input; do not mix in a staged root.

SOURCE_ROOT="${AUZIX_SOURCE_ROOT:-/mnt/ns1/AuziX/src}"
BASE_ISO="${AUZIX_BASE_ISO:-${SOURCE_ROOT}/artifacts/auzix/auzix-live-theme-app-candidate.iso}"
BASE_ISO_SHA256="${AUZIX_BASE_ISO_SHA256:-dbc37d309059b70cc39e37b7a5e0be7d27dae770654bf3ccf7ddf7d142c25cb6}"
BASE_SQUASHFS_SHA256="${AUZIX_BASE_SQUASHFS_SHA256:-7e2cc1a249e76c2711dd3659fc5485637229e9afd158584b6c937104ed37220a}"
KEY_FILE="${AUZIX_AUTHORIZED_KEYS_FILE:-/mnt/ns1/AuziX/runtime/keys/authorized_keys}"
ROOT_PASSWORD_HASH_FILE="${AUZIX_ROOT_PASSWORD_HASH_FILE:-/mnt/ns1/AuziX/runtime/secrets/live-root-shadow}"
PUBLISH_DIR="${AUZIX_PUBLISH_DIR:-${SOURCE_ROOT}/artifacts/auzix}"
RECEIPT_DIR="${AUZIX_RECEIPT_DIR:-/mnt/ns1/AuziX/build-receipts}"
WORK_ROOT="${AUZIX_WORK_ROOT:-/var/lib/auzix-build}"
BUILDER_IMAGE="${AUZIX_BUILDER_IMAGE:-auzix/builder:lab}"
REQUESTED_SOURCE_COMMIT="${AUZIX_SOURCE_COMMIT:-unknown}"
SOURCE_COMMIT="${REQUESTED_SOURCE_COMMIT}"
RUN_ID="${AUZIX_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
ISO_NAME="${AUZIX_ISO_NAME:-auzix-live-recovery-${RUN_ID}.iso}"

fail() { printf '[auzix-live-recovery] FAIL: %s\n' "$*" >&2; exit 1; }
log() { printf '[auzix-live-recovery] %s\n' "$*"; }

[[ -f "${BASE_ISO}" ]] || fail "base ISO missing: ${BASE_ISO}"
[[ -s "${KEY_FILE}" ]] || fail 'authorized-keys input missing'
[[ -s "${ROOT_PASSWORD_HASH_FILE}" ]] || fail 'root password hash input missing'
if [[ -d "${SOURCE_ROOT}/.git" ]]; then
  [[ "${SOURCE_COMMIT}" != unknown ]] || fail 'AUZIX_SOURCE_COMMIT must name the committed source under test'
  [[ -z "$(git -C "${SOURCE_ROOT}" status --porcelain)" ]] || fail 'source checkout is dirty; commit the intended delta first'
  [[ "$(git -C "${SOURCE_ROOT}" rev-parse HEAD)" == "${SOURCE_COMMIT}" ]] || fail 'AUZIX_SOURCE_COMMIT does not match source checkout HEAD'
else
  [[ -s "${SOURCE_ROOT}/.auzix-source-commit" ]] || fail 'exported source is missing .auzix-source-commit'
  SOURCE_COMMIT="$(tr -d '[:space:]' <"${SOURCE_ROOT}/.auzix-source-commit")"
  [[ -n "${SOURCE_COMMIT}" ]] || fail 'exported source commit marker is empty'
  if [[ "${REQUESTED_SOURCE_COMMIT}" != unknown && "${REQUESTED_SOURCE_COMMIT}" != "${SOURCE_COMMIT}" ]]; then
    log "legacy controller requested ${REQUESTED_SOURCE_COMMIT}; authoritative export marker selects ${SOURCE_COMMIT}"
  fi
fi
command -v docker >/dev/null 2>&1 || fail 'docker is required on the R730 worker'

actual_base_sha="$(sha256sum "${BASE_ISO}" | awk '{print $1}')"
[[ "${actual_base_sha}" == "${BASE_ISO_SHA256}" ]] || fail "base ISO hash mismatch: ${actual_base_sha}"

work_dir="${WORK_ROOT}/recovery/${RUN_ID}"
work_source="${work_dir}/source"
work_root="${work_dir}/AuzixRoot"
work_iso_tree="${work_dir}/iso-tree"
work_squashfs="${work_dir}/auzix-root.squashfs"
candidate="${work_dir}/${ISO_NAME}"
receipt="${RECEIPT_DIR}/live-recovery-${RUN_ID}.receipt"
log_file="${RECEIPT_DIR}/live-recovery-${RUN_ID}.log"

mkdir -p "${work_dir}" "${work_source}" "${work_root}" "${work_iso_tree}" "${RECEIPT_DIR}"
exec > >(tee "${log_file}") 2>&1

log 'snapshotting committed source to worker-local scratch'
docker run --rm \
  -v "${SOURCE_ROOT}:/source:ro" -v "${work_dir}:/work" \
  "${BUILDER_IMAGE}" sh -ec '
    rsync -a --delete --exclude .git/ --exclude out/ --exclude artifacts/ --exclude downloads/ /source/ /work/source/
  '

log 'extracting the preserved boot tree and verifying its embedded SquashFS'
docker run --rm -v "$(dirname "${BASE_ISO}"):/base:ro" -v "${work_dir}:/work" \
  "${BUILDER_IMAGE}" sh -ec '
    xorriso -osirrox on -indev "/base/'"$(basename "${BASE_ISO}")"'" -extract / /work/iso-tree >/dev/null 2>&1
  '
embedded_sha="$(sha256sum "${work_iso_tree}/live/auzix-root.squashfs" | awk '{print $1}')"
[[ "${embedded_sha}" == "${BASE_SQUASHFS_SHA256}" ]] || fail "base SquashFS hash mismatch: ${embedded_sha}"
docker run --rm -v "${work_dir}:/work" "${BUILDER_IMAGE}" sh -ec '
  unsquashfs -no-xattrs -d /work/AuzixRoot /work/iso-tree/live/auzix-root.squashfs >/dev/null
'

log 'applying the bounded live-access, installer, package-control, and desktop-asset deltas'
docker run --rm \
  -v "${work_dir}:/work" \
  -v "${KEY_FILE}:/run/auzix-runtime/authorized_keys:ro" \
  -v "${ROOT_PASSWORD_HASH_FILE}:/run/auzix-runtime/live-root-shadow:ro" \
  -w /work/source "${BUILDER_IMAGE}" sh -ec '
    AUZIX_ACCESS_PROFILE=lab-password \
    AUZIX_AUTHORIZED_KEYS_SOURCE=/run/auzix-runtime/authorized_keys \
    AUZIX_ROOT_PASSWORD_HASH_FILE=/run/auzix-runtime/live-root-shadow \
      ./scripts/stage-auzix-live-access.sh /work/AuzixRoot
    installer_version=$(basename "$(readlink /work/AuzixRoot/Programs/AuzixInstaller/current)")
    installer_resources=/work/AuzixRoot/Programs/AuzixInstaller/${installer_version}/Resources
    test -d "${installer_resources}"
    install -m 0644 installer/auzix-installer.lua "${installer_resources}/auzix-installer.lua"
    install -m 0644 installer/install-plan.schema.json "${installer_resources}/install-plan.schema.json"
    install -m 0644 installer/questions.json "${installer_resources}/questions.json"
    install -m 0644 installer/plans/default.json "${installer_resources}/plans/default.json"
    install -m 0644 installer/install-plan.schema.json /work/AuzixRoot/System/Settings/installer/install-plan.schema.json
    install -m 0644 installer/questions.json /work/AuzixRoot/System/Settings/installer/questions.json
    install -m 0644 installer/plans/default.json /work/AuzixRoot/System/Settings/installer/plans/default.json
    gcc -D_GNU_SOURCE -O2 -Wall -Wextra -Werror \
      -o /work/auzix-installer-efl installer/efl/auzix-installer-efl.c \
      $(pkg-config --cflags --libs elementary)
    AUZIX_EFL_INSTALLER_BINARY=/work/auzix-installer-efl \
      ./scripts/build-auzix-installer-efl-package.sh /work/AuzixRoot
    gcc -D_GNU_SOURCE -O2 -Wall -Wextra -Werror \
      -o /work/auzix-package-manager-efl installer/efl/auzix-package-manager-efl.c \
      $(pkg-config --cflags --libs elementary)
    AUZIX_EFL_PACKAGE_MANAGER_BINARY=/work/auzix-package-manager-efl \
      ./scripts/build-auzix-package-manager-efl-package.sh /work/AuzixRoot
    ./scripts/build-auzix-desktop-assets-package.sh /work/AuzixRoot
    enlightenment_version=$(basename "$(readlink /work/AuzixRoot/Programs/Enlightenment/current)")
    enlightenment_commands=/work/AuzixRoot/Programs/Enlightenment/${enlightenment_version}/Commands
    test -d "${enlightenment_commands}"
    if test -x "${enlightenment_commands}/enlightenment_remote" && \
       ! test -e "${enlightenment_commands}/enlightenment_remote.elive"; then
      mv "${enlightenment_commands}/enlightenment_remote" \
        "${enlightenment_commands}/enlightenment_remote.elive"
    fi
    test -x "${enlightenment_commands}/enlightenment_remote.elive"
    install -m 0755 scripts/enlightenment_remote-auzix \
      "${enlightenment_commands}/enlightenment_remote"
    mkdir -p /work/AuzixRoot/System/State/packages /work/AuzixRoot/System/Logs/packages
    chown -R 0:1000 /work/AuzixRoot/System/State/packages /work/AuzixRoot/System/Logs/packages
    chmod 0775 /work/AuzixRoot/System/State/packages /work/AuzixRoot/System/Logs/packages
  '

log 'packing only the recovered root payload; preserved kernel and boot map remain unchanged'
docker run --rm -v "${work_dir}:/work" "${BUILDER_IMAGE}" sh -ec '
  mksquashfs /work/AuzixRoot /work/auzix-root.squashfs -noappend -comp gzip >/dev/null
  test -s /work/auzix-root.squashfs
'

docker run --rm \
  -v "$(dirname "${BASE_ISO}"):/base:ro" -v "${work_dir}:/work" "${BUILDER_IMAGE}" sh -ec '
    cp /work/auzix-root.squashfs /work/iso-tree/live/auzix-root.squashfs
    xorriso -as mkisofs -r -J -V AUZIXLIVE \
      --grub2-mbr --interval:local_fs:0s-15s:zero_mbrpt,zero_gpt,zero_apm:"/base/'"$(basename "${BASE_ISO}")"'" \
      --protective-msdos-label -partition_cyl_align off -partition_offset 0 \
      -partition_hd_cyl 70 -partition_sec_hd 32 -apm-block-size 2048 -hfsplus \
      -efi-boot-part --efi-boot-image -c /boot.catalog \
      -b /boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 \
      -boot-info-table --grub2-boot-info -eltorito-alt-boot \
      -e /efi.img -no-emul-boot -boot-load-size 5760 \
      -o "/work/'"${ISO_NAME}"'" /work/iso-tree
  '
[[ -s "${candidate}" ]] || fail 'candidate ISO was not created'

log 'validating boot map and bounded payload'
docker run --rm -v "${work_source}:/source:ro" -v "${work_dir}:/work:ro" \
  -e AUZIX_REQUIRE_WRITABLE_MOUNT_HANDOFF=0 \
  "${BUILDER_IMAGE}" /source/scripts/validate-auzix-boot-iso.sh "/work/${ISO_NAME}"

mkdir -p "${work_dir}/verify-root"
docker run --rm -v "${work_dir}:/work" "${BUILDER_IMAGE}" sh -ec '
  unsquashfs -no-xattrs -d /work/verify-root /work/auzix-root.squashfs >/dev/null
  grep -qx "PermitRootLogin yes" /work/verify-root/System/Settings/ssh/sshd_config
  grep -qx "PasswordAuthentication yes" /work/verify-root/System/Settings/ssh/sshd_config
  test -s /work/verify-root/Users/root/.ssh/authorized_keys
  test -L /work/verify-root/Programs/AuzixInstallerEfl/current
  test "$(readlink /work/verify-root/System/Tools/auzix-installer)" = "/Programs/AuzixInstaller/current/Commands/auzix-installer"
  test -s /work/verify-root/System/Settings/installer/install-plan.schema.json
  test -x /work/verify-root/Programs/AuzixInstallerEfl/0.1/Commands/efl.real
  test -L /work/verify-root/Programs/AuzixInstaller/0.2/Frontends/efl
  test "$(readlink /work/verify-root/System/Tools/launch-auzix-installer)" = "/Programs/AuzixInstallerEfl/current/Commands/launch-auzix-installer"
  grep -Fq "/Programs/AuzixInstallerEfl/current/Commands/efl" /work/verify-root/Programs/AuzixInstallerEfl/0.1/Commands/launch-auzix-installer
  test -x /work/verify-root/Programs/AuzixPackageManagerEfl/0.1/Commands/efl.real
  test "$(readlink /work/verify-root/System/Tools/auzix-package-manager)" = "/Programs/AuzixPackageManagerEfl/current/Commands/efl"
  grep -Fxq "Exec=/System/Tools/auzix-package-manager" /work/verify-root/System/Compatibility/usr/share/applications/auzix-package-manager.desktop
  test -s /work/verify-root/System/PackageDB/AuzixPackageManagerEfl-0.1.auzix.json
  test "$(stat -c %u:%g /work/verify-root/System/State/packages)" = "0:1000"
  test "$(stat -c %a /work/verify-root/System/State/packages)" = "775"
  test "$(stat -c %u:%g /work/verify-root/System/Logs/packages)" = "1000:1000"
  test -s /work/verify-root/System/Compatibility/etc/ssl/certs/ca-certificates.crt
  test -s /work/verify-root/Users/auzix/.e/e/config/standard/e.cfg
  test -L /work/verify-root/System/Settings/display/assets
  test -f /work/verify-root/Programs/DesktopAssets/auzietek/Resources/display/assets/themes/E20-Scifi-theme.edj
  test -e /work/verify-root/System/Compatibility/usr/share/elementary/themes/E20-Scifi-theme.edj
  test -e /work/verify-root/System/Compatibility/usr/share/terminology/themes/Scifi-terminology-theme.edj
  test ! -e /work/verify-root/System/Compatibility/usr/share/elementary/themes/Scifi-terminology-theme.edj
  enlightenment_version=$(basename "$(readlink /work/verify-root/Programs/Enlightenment/current)")
  enlightenment_commands=/work/verify-root/Programs/Enlightenment/${enlightenment_version}/Commands
  test -x "${enlightenment_commands}/enlightenment_remote"
  test -x "${enlightenment_commands}/enlightenment_remote.elive"
  HOME=/work/verify-root/Users/auzix sh \
    "${enlightenment_commands}/enlightenment_remote" \
      -theme-dir-list | grep -Fxq /System/Compatibility/usr/share/elementary/themes
'

candidate_sha="$(sha256sum "${candidate}" | awk '{print $1}')"
candidate_squashfs_sha="$(sha256sum "${work_squashfs}" | awk '{print $1}')"
install -m 0644 "${candidate}" "${PUBLISH_DIR}/${ISO_NAME}"
printf '%s  %s\n' "${candidate_sha}" "${ISO_NAME}" >"${PUBLISH_DIR}/${ISO_NAME}.sha256"

cat >"${receipt}" <<EOF
format=auzix-live-recovery-receipt-v1
status=pass
run_id=${RUN_ID}
worker=r730-ai-01
source_commit=${SOURCE_COMMIT}
base_iso=${BASE_ISO}
base_iso_sha256=${BASE_ISO_SHA256}
base_squashfs_sha256=${BASE_SQUASHFS_SHA256}
root_input=embedded-base-squashfs
deltas=live-access,installer-backend,installer-efl,package-manager-efl,desktop-assets,enlightenment-remote-wrapper
iso_path=${PUBLISH_DIR}/${ISO_NAME}
iso_sha256=${candidate_sha}
squashfs_sha256=${candidate_squashfs_sha}
finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

log "PASS iso=${PUBLISH_DIR}/${ISO_NAME} receipt=${receipt}"
