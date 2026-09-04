#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="${1:?usage: build-auzix-alpha-hdd-image.sh RUN_ID}"
IMAGE="${AUZIX_ALPHA_IMAGE:-auzix/alpha:pre-hdd-salvage-20260831-r8}"
ANCHOR_ISO="${AUZIX_ALPHA_ANCHOR_ISO:?set AUZIX_ALPHA_ANCHOR_ISO to the known-good ISO}"
BUILD_ROOT="${AUZIX_BUILD_ROOT_DIR:-/var/lib/auzix-build}"
WORK="${BUILD_ROOT}/alpha-hdd/${RUN_ID}"
ROOT="${WORK}/root"
KERNEL_RELEASE="${AUZIX_ALPHA_KERNEL_RELEASE:-6.1.0-48-amd64}"

test "$(id -u)" -eq 0 || { echo 'alpha HDD build requires root' >&2; exit 1; }
test ! -e "${WORK}" || { echo "immutable run already exists: ${WORK}" >&2; exit 1; }
mkdir -p "${WORK}"
complete=0
finish() {
  rc=$?
  if [[ "${complete}" = 1 ]]; then
    printf 'complete\n' >"${WORK}/run.status"
  elif [[ ! -e "${WORK}/run.status" ]]; then
    printf 'failed rc=%s\n' "${rc}" >"${WORK}/run.status"
  fi
}
trap finish EXIT

"${ROOT_DIR}/scripts/stage-auzix-alpha-hdd-root.sh" \
  "${IMAGE}" "${ANCHOR_ISO}" "${ROOT}"

# /run is intentionally an empty mountpoint in the installed image. Materialize
# sshd's volatile directory only for the offline configuration preflight.
mkdir -p "${ROOT}/run/sshd"
chmod 0755 "${ROOT}/run/sshd"
chroot "${ROOT}" /Programs/BusyBox/current/Commands/busybox sh -c '
  set -e
  . /System/Settings/auzix-runtime-env
  sshd -t
  python3 -c "import ssl, sqlite3, ctypes, bz2, lzma"
  abiword --version >/dev/null
  ldd /Programs/Midori/current/Resources/midori/libmozgtk.so >/dev/null
'
rmdir "${ROOT}/run/sshd"

# This is an explicitly receipted alpha-salvage exception: the userspace was
# validated in the pre-HDD container, while the established writer continues
# to own partitioning, initramfs construction, GRUB, checksum, and finalization.
AUZIX_ROOT_SOURCE="${ROOT}" \
AUZIX_BUILD_ROOT=0 \
AUZIX_INCLUDE_OPENSSH=1 \
AUZIX_KERNEL_IMAGE="${ROOT}/boot/vmlinuz-${KERNEL_RELEASE}" \
AUZIX_KERNEL_RELEASE="${KERNEL_RELEASE}" \
AUZIX_IMG_WORK_DIR="${WORK}/media-work" \
AUZIX_IMG_NAME="auzix-alpha-${RUN_ID}.img" \
AUZIX_IMG_SIZE="${AUZIX_IMG_SIZE:-8192M}" \
"${ROOT_DIR}/scripts/build-auzix-live-disk-image.sh"

complete=1
printf 'alpha-hdd-build: PASS run=%s image=%s\n' \
  "${RUN_ID}" "${ROOT_DIR}/artifacts/auzix/auzix-alpha-${RUN_ID}.img"
