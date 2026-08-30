#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${ROOT_DIR}/artifacts/auzix"
WORK_DIR="${AUZIX_IMG_WORK_DIR:-${ROOT_DIR}/out/auzix-live-img}"
IMG_NAME="${AUZIX_IMG_NAME:-auzix-live-thumbdrive.img}"
IMG_PATH="${ARTIFACT_DIR}/${IMG_NAME}"
# Keep the produced raw image sparse, but give the writable filesystem enough
# room for first-boot logs, installer state, and package smoke tests.  The
# compressed/exported artifact can stay small; the mounted RW filesystem cannot
# be sized like a squashfs/ISO payload.
IMG_SIZE="${AUZIX_IMG_SIZE:-8192M}"
MIN_FREE_MB="${AUZIX_IMG_MIN_FREE_MB:-512}"
LIVE_ROOT_MODE="${AUZIX_LIVE_ROOT_MODE:-iso-root}"
ISO_WORK_DIR="${WORK_DIR}/iso-work"
ISO_NAME="${AUZIX_IMG_SEED_ISO_NAME:-.auzix-live-img-seed.iso}"
ISO_TREE="${ISO_WORK_DIR}/iso"
ROOT_SOURCE="${AUZIX_ROOT_SOURCE:-}"
DEFAULT_ROOT="${ROOT_DIR}/out/auzix-strict/AuzixRoot"
FALLBACK_ROOT="${ROOT_DIR}/out/auzix-strict/AuzixRoot-pruned"
IMAGE_ROOT=""
BUILD_ROOT="${AUZIX_BUILD_ROOT:-1}"
LOOP_DEV=""
MNT_ROOT=""

log() {
  printf '[auzix-live-img] %s\n' "$*" >&2
}

fail() {
  printf '[auzix-live-img] FAIL: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

ensure_loop_partition_node() {
  local loop_dev="$1"
  local part_no="$2"
  local node="${loop_dev}p${part_no}"
  local base sys_name devno major minor

  [[ -b "${node}" ]] && return 0
  base="$(basename "${loop_dev}")"
  sys_name="/sys/block/${base}/${base}p${part_no}/dev"
  [[ -r "${sys_name}" ]] || return 1
  devno="$(cat "${sys_name}")"
  major="${devno%:*}"
  minor="${devno#*:}"
  mknod "${node}" b "${major}" "${minor}" 2>/dev/null || true
  [[ -b "${node}" ]]
}

cleanup() {
  set +e
  if [[ -n "${MNT_ROOT}" ]]; then umount "${MNT_ROOT}" >/dev/null 2>&1; fi
  if [[ -n "${LOOP_DEV}" ]]; then losetup -d "${LOOP_DEV}" >/dev/null 2>&1; fi
}
trap cleanup EXIT

if [[ "$(id -u)" != "0" ]]; then
  fail "disk image assembly needs root for loop devices, mkfs, and GRUB install"
fi

need truncate
need parted
need losetup
need mkfs.ext4
need grub-install
need chroot
[[ -f /usr/lib/grub/i386-pc/modinfo.sh || -f /usr/lib/grub2/i386-pc/modinfo.sh || -f /usr/share/grub2/i386-pc/modinfo.sh ]] \
  || fail "BIOS GRUB modules missing; install grub-pc-bin on Debian-like builders"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${ARTIFACT_DIR}"

log "creating ${IMG_SIZE} raw disk image: ${IMG_PATH}"
rm -f "${IMG_PATH}" "${IMG_PATH}.sha256"
truncate -s "${IMG_SIZE}" "${IMG_PATH}"

LOOP_DEV="$(losetup --find --show --partscan "${IMG_PATH}")"
log "loop=${LOOP_DEV}"

log "partitioning MBR installed-root layout matching auzix-install-disk"
parted -s "${LOOP_DEV}" mklabel msdos
parted -s "${LOOP_DEV}" mkpart primary ext4 1MiB 100%
parted -s "${LOOP_DEV}" set 1 boot on || true
partprobe "${LOOP_DEV}" >/dev/null 2>&1 || true
partx -u "${LOOP_DEV}" >/dev/null 2>&1 || partx -a "${LOOP_DEV}" >/dev/null 2>&1 || true
sleep 1
ensure_loop_partition_node "${LOOP_DEV}" 1 || true

ROOT_PART="${LOOP_DEV}p1"
if [[ ! -e "${ROOT_PART}" && -e "${LOOP_DEV}1" ]]; then ROOT_PART="${LOOP_DEV}1"; fi
if [[ ! -b "${ROOT_PART}" ]]; then
  log "partition node diagnostics for ${LOOP_DEV}:"
  ls -l "${LOOP_DEV}"* >&2 2>/dev/null || true
  partx -s "${LOOP_DEV}" >&2 2>/dev/null || true
fi
[[ -b "${ROOT_PART}" ]] || fail "root partition node not found for ${LOOP_DEV}"

mkfs.ext4 -q -F -L AUZIXROOT "${ROOT_PART}"

MNT_ROOT="${WORK_DIR}/mnt-root"
mkdir -p "${MNT_ROOT}"
mount "${ROOT_PART}" "${MNT_ROOT}"

if [[ "${BUILD_ROOT}" == "1" && -z "${ROOT_SOURCE}" ]]; then
  ISO_WORK_DIR="${MNT_ROOT}/.auzix-build/boot-work"
  ISO_TREE="${ISO_WORK_DIR}/iso"
  log "building AUZiX root with the same strict-all sequence used by ISO builds"
  env AUZIX_STRICT_ROOT_ONLY=1 \
    AUZIX_INCLUDE_OPENSSH="${AUZIX_INCLUDE_OPENSSH:-0}" \
    AUZIX_LINK_MODE="${AUZIX_LINK_MODE:-strict}" \
    AUZIX_LEGACY_POLICY="${AUZIX_LEGACY_POLICY:-strict}" \
    AUZIX_STRICT_ROOT_AUDIT_MODE="${AUZIX_STRICT_ROOT_AUDIT_MODE:-fail}" \
    AUZIX_SKIP_ELF_NORMALIZE="${AUZIX_SKIP_ELF_NORMALIZE:-0}" \
    AUZIX_INCLUDE_LIVE_ASSETS="${AUZIX_INCLUDE_LIVE_ASSETS:-0}" \
    AUZIX_INCLUDE_ISO_ASSETS="${AUZIX_INCLUDE_ISO_ASSETS:-1}" \
    AUZIX_INCLUDE_LIVE_NATIVE_MIRRORS="${AUZIX_INCLUDE_LIVE_NATIVE_MIRRORS:-0}" \
    AUZIX_LIVE_CURRENT_ONLY="${AUZIX_LIVE_CURRENT_ONLY:-1}" \
    "${ROOT_DIR}/scripts/build-auzix-strict-all.sh"
  IMAGE_ROOT="${DEFAULT_ROOT}"
else
  if [[ -z "${ROOT_SOURCE}" ]]; then
    if [[ -d "${DEFAULT_ROOT}" ]]; then
      ROOT_SOURCE="${DEFAULT_ROOT}"
    elif [[ -d "${FALLBACK_ROOT}" ]]; then
      ROOT_SOURCE="${FALLBACK_ROOT}"
    else
      fail "no AUZiX root found; set AUZIX_ROOT_SOURCE or use AUZIX_BUILD_ROOT=1"
    fi
  fi
  IMAGE_ROOT="${ROOT_SOURCE}"
  log "using prebuilt AUZiX root source without copying: ${IMAGE_ROOT}"
fi

case "${AUZIX_INCLUDE_OPENSSH:-0}" in
  1|yes|true|on) ;;
  *)
    # BusyBox is the live/HDD rescue spine.  Remove stale OpenSSH assets only
    # from the image-local build root; do not mutate an external ROOT_SOURCE.
    if [[ "${IMAGE_ROOT}" == "${MNT_ROOT}/"* ]]; then
      log "stripping OpenSSH from image-local root; live access remains BusyBox/rescue"
      rm -rf \
        "${IMAGE_ROOT}/Programs/OpenSSH" \
        "${IMAGE_ROOT}/Services/ssh" \
        "${IMAGE_ROOT}/System/Settings/ssh" \
        "${IMAGE_ROOT}/System/State/ssh" \
        "${IMAGE_ROOT}/System/PackageDB/OpenSSH-"*.auzix.json
    fi
    ;;
esac

log "assembling boot payload with existing ISO spine onto mounted image"
AUZIX_ISO_WORK_DIR="${ISO_WORK_DIR}" \
AUZIX_ISO_NAME="${ISO_NAME}" \
AUZIX_ROOT_SOURCE="${IMAGE_ROOT}" \
AUZIX_LIVE_ROOT_MODE="${LIVE_ROOT_MODE}" \
AUZIX_BOOT_ASSEMBLE_ONLY=1 \
"${ROOT_DIR}/scripts/build-auzix-boot-iso.sh" >/dev/null

[[ -d "${ISO_TREE}/boot" ]] || fail "seed boot tree missing /boot: ${ISO_TREE}"

log "laying AUZiX installed root onto HDD partition"
(
  cd "${IMAGE_ROOT}"
  tar \
    --exclude='./dev/*' \
    --exclude='./proc/*' \
    --exclude='./sys/*' \
    --exclude='./run/*' \
    --exclude='./.auzix-build/*' \
    --exclude='./Work/Temp/*' \
    --exclude='./Work/InstallTarget/*' \
    -cf - .
) | (
  cd "${MNT_ROOT}"
  tar -xf -
)

free_mb="$(df -Pm "${MNT_ROOT}" | awk 'NR == 2 {print $4}')"
if [[ "${free_mb:-0}" -lt "${MIN_FREE_MB}" ]]; then
  fail "installed root left only ${free_mb:-0}MiB free on ${IMG_SIZE} image; increase AUZIX_IMG_SIZE or prune payload"
fi
log "installed root free space: ${free_mb}MiB"

mkdir -p "${MNT_ROOT}/boot" "${MNT_ROOT}/dev" "${MNT_ROOT}/proc" "${MNT_ROOT}/sys" "${MNT_ROOT}/run"
cp -a "${ISO_TREE}/boot/." "${MNT_ROOT}/boot/"
if [[ -x "${MNT_ROOT}/System/Boot/InstalledInit" ]]; then
  cp -a "${MNT_ROOT}/System/Boot/InstalledInit" "${MNT_ROOT}/init"
else
  cp -a "${MNT_ROOT}/System/Boot/StartSequence" "${MNT_ROOT}/init"
fi
chmod 0755 "${MNT_ROOT}/init"
# The strict-all root sequence already ran add-auzix-live-tools/finalizer before
# this media writer stage. Do not execute target-root scripts directly from the
# builder host: their shebangs intentionally point at AUZiX-internal paths.
mkdir -p \
  "${MNT_ROOT}/System/Logs/display" \
  "${MNT_ROOT}/System/State/display" \
  "${MNT_ROOT}/System/State/desktop" \
  "${MNT_ROOT}/System/State/packages" \
  "${MNT_ROOT}/System/Settings/packages" \
  "${MNT_ROOT}/System/Logs/packages"
chmod 0755 \
  "${MNT_ROOT}" \
  "${MNT_ROOT}/System" \
  "${MNT_ROOT}/System/Logs" \
  "${MNT_ROOT}/System/State" \
  "${MNT_ROOT}/Users"
chmod 0775 \
  "${MNT_ROOT}/System/Logs/display" \
  "${MNT_ROOT}/System/State/display" \
  "${MNT_ROOT}/System/State/desktop"
chown -R 1000:1000 \
  "${MNT_ROOT}/System/Logs/display" \
  "${MNT_ROOT}/System/State/display" \
  "${MNT_ROOT}/System/State/desktop" \
  "${MNT_ROOT}/Users/auzix" 2>/dev/null || true
chmod 0775 "${MNT_ROOT}/System/State/packages" "${MNT_ROOT}/System/Logs/packages"
chown 0:1000 "${MNT_ROOT}/System/State/packages" "${MNT_ROOT}/System/Logs/packages" 2>/dev/null || true

# HDD images boot as already-installed roots. Seed the package-manager state
# from the receipts that the root builder laid down, otherwise first-boot
# installs treat base packages as missing and can re-touch live core links/libs.
if [[ -d "${MNT_ROOT}/System/PackageDB" ]]; then
  tmp_installed="${MNT_ROOT}/System/State/packages/installed.json.tmp.$$"
  tmp_records="${MNT_ROOT}/System/State/packages/installed.records.$$.jsonl"
  : >"${tmp_records}"
  while IFS= read -r -d '' receipt; do
    receipt_name="/System/PackageDB/$(basename "${receipt}")"
    jq -c --arg receipt "${receipt_name}" '
      select(.name != null)
      | {
          name: .name,
          version: (.version // ""),
          kind: (.kind // "unknown"),
          package: (.package // ""),
          sha256: (.sha256 // ""),
          description: (.description // .notes // ""),
          receipt: $receipt,
          prefix: (.prefix // .paths.prefix // ""),
          commands: (.commands // []),
          desktop_entries: (.desktop_entries // []),
          compatibility_exports: (.compatibility_exports // []),
          depends: (.depends // []),
          recommends: (.recommends // []),
          provides: (.provides // []),
          source_metadata: (.source // {}),
          runtime_ladder: (.runtime_ladder // null),
          runtime_environment: (.runtime_environment // null),
          permissions: (.permissions // null),
          validation: (.validation // null),
          source: "hdd-image-bootstrap-receipts",
          installed_at: "hdd-image-bootstrap-receipts"
        }
    ' "${receipt}" >>"${tmp_records}"
  done < <(find "${MNT_ROOT}/System/PackageDB" -maxdepth 1 -type f \
    \( -name '*.auzix.json' -o -name '*.json' \) -print0)
  jq -s '
      {
        format: "auzix-installed-v1",
        installed: (
          unique_by((.name // "") | ascii_downcase)
          | sort_by((.name // "") | ascii_downcase)
        )
      }
    ' "${tmp_records}" >"${tmp_installed}"
  if [[ -s "${tmp_installed}" ]]; then
    mv -f "${tmp_installed}" "${MNT_ROOT}/System/State/packages/installed.json"
    cp -f "${MNT_ROOT}/System/State/packages/installed.json" \
      "${MNT_ROOT}/System/Settings/packages/installed.json"
  else
    rm -f "${tmp_installed}"
    printf '%s\n' '{"format":"auzix-installed-v1","installed":[]}' \
      >"${MNT_ROOT}/System/State/packages/installed.json"
  fi
  rm -f "${tmp_records}"
fi

log "finalizing installed root inside target chroot"
if [[ -x "${MNT_ROOT}/System/Tools/finalize-installed-root" ]]; then
  chroot "${MNT_ROOT}" /Programs/BusyBox/current/Commands/busybox env \
    AUZIX_LINK_MODE="${AUZIX_LINK_MODE:-strict}" \
    /System/Tools/finalize-installed-root /
else
  fail "installed root finalizer missing: /System/Tools/finalize-installed-root"
fi

if [[ -x "${MNT_ROOT}/Programs/AuzixDesktopIntegration/current/Commands/activate" ]]; then
  log "activating desktop integration inside target chroot"
  chroot "${MNT_ROOT}" /Programs/BusyBox/current/Commands/busybox env \
    AUZIX_PACKAGE_NAME=AuzixDesktopIntegration \
    /Programs/AuzixDesktopIntegration/current/Commands/activate || true
fi
if [[ -x "${MNT_ROOT}/Programs/AuzixDesktopIntegration/current/Commands/e-launcher-sync" ]]; then
  log "syncing Enlightenment launcher seed inside target chroot"
  chroot "${MNT_ROOT}" /Programs/BusyBox/current/Commands/busybox env \
    AUZIX_PACKAGE_NAME=AuzixDesktopIntegration \
    /Programs/AuzixDesktopIntegration/current/Commands/e-launcher-sync || true
fi

if [[ -x "${MNT_ROOT}/Programs/AuzixPackageTools/current/Commands/auzix-pkg" ]]; then
  log "refreshing installed-root runtime linker cache"
  chroot "${MNT_ROOT}" /Programs/BusyBox/current/Commands/busybox env \
    /Programs/AuzixPackageTools/current/Commands/auzix-pkg refresh-ldcache || true
fi

if [[ -x "${ROOT_DIR}/scripts/probe-auzix-desktop-launchers.sh" ]]; then
  log "recording installed-root desktop launcher probe"
  mkdir -p "${MNT_ROOT}/System/Logs/packages"
  "${ROOT_DIR}/scripts/probe-auzix-desktop-launchers.sh" "${MNT_ROOT}" \
    >"${MNT_ROOT}/System/Logs/packages/desktop-launcher-probe-build.txt" 2>&1 || true
fi

cat >"${MNT_ROOT}/System/Settings/fstab" <<'EOF'
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620,ptmxmode=666 0 0
tmpfs /dev/shm tmpfs mode=1777,nosuid,nodev 0 0
tmpfs /run tmpfs defaults 0 0
LABEL=AUZIXROOT / ext4 defaults 0 1
EOF
mkdir -p "${MNT_ROOT}/System/State/install"
cat >"${MNT_ROOT}/System/State/install/storage-layout.txt" <<EOF
root_build_mode=hdd-image-installed-root
layout=whole
root=LABEL=AUZIXROOT
writer=build-auzix-live-disk-image.sh
EOF
cat >"${MNT_ROOT}/boot/grub/grub.cfg" <<'EOF'
set timeout=3
set default=0

menuentry "AuziX installed root" {
    linux /boot/vmlinuz console=ttyS0,115200 console=tty0 root=LABEL=AUZIXROOT auzix.root=LABEL=AUZIXROOT init=/init rw
    initrd /boot/initramfs.cpio.gz
}
EOF

log "installing BIOS GRUB"
grub-install --target=i386-pc --boot-directory="${MNT_ROOT}/boot" --recheck "${LOOP_DEV}" >/dev/null

sync
umount "${MNT_ROOT}"
MNT_ROOT=""
losetup -d "${LOOP_DEV}"
LOOP_DEV=""

sha256sum "${IMG_PATH}" >"${IMG_PATH}.sha256"
ls -lh "${IMG_PATH}" "${IMG_PATH}.sha256"
log "Bootable raw disk image ready: ${IMG_PATH}"
