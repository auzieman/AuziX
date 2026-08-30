#!/usr/bin/env bash
set -euo pipefail

# Static publication gate for a bootable AuziX ISO.  This is intentionally
# cheaper than a VM boot: it catches the old BIOS-only artifact and missing
# live-root handoff before an ISO reaches a Proxmox or physical target.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_PATH="${1:-${ROOT_DIR}/artifacts/auzix/auzix-strict-shell.iso}"
REQUIRE_UEFI="${AUZIX_REQUIRE_UEFI:-1}"
REQUIRE_WRITABLE_MOUNT_HANDOFF="${AUZIX_REQUIRE_WRITABLE_MOUNT_HANDOFF:-1}"
EXPECTED_LINK_MODE="${AUZIX_EXPECT_LINK_MODE:-${AUZIX_LINK_MODE:-strict}}"
REQUIRE_LIVE_SSH="${AUZIX_REQUIRE_LIVE_SSH:-0}"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "required command missing: $1"; }

need xorriso
need bsdtar
need unsquashfs
test -f "${ISO_PATH}" || fail "ISO not found: ${ISO_PATH}"

report="$(xorriso -indev "${ISO_PATH}" -report_el_torito plain 2>&1)"
printf '%s\n' "${report}"

grep -q 'El Torito boot img :.*BIOS' <<<"${report}" || fail 'BIOS El Torito boot image is missing'
if [[ "${REQUIRE_UEFI}" == "1" ]]; then
  grep -q 'El Torito boot img :.*UEFI' <<<"${report}" || fail 'UEFI El Torito boot image is missing'
fi
grep -q "Volume id    : 'AUZIXLIVE'" <<<"${report}" || fail 'ISO volume id is not AUZIXLIVE'

entries="$(bsdtar -tf "${ISO_PATH}")"
for path in boot/vmlinuz boot/initramfs.cpio.gz boot/grub/grub.cfg live/auzix-root.squashfs; do
  grep -qx "${path}" <<<"${entries}" || fail "missing ISO payload: /${path}"
done

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
xorriso -osirrox on -indev "${ISO_PATH}" -extract /boot/grub/grub.cfg "${tmp_dir}/grub.cfg" >/dev/null 2>&1
xorriso -osirrox on -indev "${ISO_PATH}" -extract /boot/initramfs.cpio.gz "${tmp_dir}/initramfs.cpio.gz" >/dev/null 2>&1
xorriso -osirrox on -indev "${ISO_PATH}" -extract /live/auzix-root.squashfs "${tmp_dir}/auzix-root.squashfs" >/dev/null 2>&1

grep -q 'console=ttyS0,115200' "${tmp_dir}/grub.cfg" || fail 'serial console boot argument is missing'
case "${EXPECTED_LINK_MODE}" in
  strict)
    grep -q 'auzix.links=strict' "${tmp_dir}/grub.cfg" || fail 'strict alias boot argument is missing'
    ;;
  compat)
    grep -q 'auzix.links=compat' "${tmp_dir}/grub.cfg" || fail 'compat alias boot argument is missing'
    ;;
  none|relaxed)
    if grep -q 'auzix.links=strict' "${tmp_dir}/grub.cfg"; then
      fail 'strict alias boot argument is present in relaxed/no-link validation mode'
    fi
    ;;
  *)
    fail "unknown AUZIX_EXPECT_LINK_MODE=${EXPECTED_LINK_MODE}"
    ;;
esac
mkdir "${tmp_dir}/initramfs"
(cd "${tmp_dir}/initramfs" && gzip -dc "${tmp_dir}/initramfs.cpio.gz" | cpio -idmu 2>/dev/null)
test -f "${tmp_dir}/initramfs/init" || fail 'initramfs /init is missing'
head -n 1 "${tmp_dir}/initramfs/init" | grep -Fx '#!/Programs/BusyBox/1.36.1/Commands/busybox sh' >/dev/null || fail 'initramfs /init must use the static BusyBox interpreter directly'
grep -q 'auzix-root.squashfs' "${tmp_dir}/initramfs/init" || fail 'initramfs does not mount the SquashFS root'
grep -q 'refusing readonly desktop fallback' "${tmp_dir}/initramfs/init" || fail 'initramfs permits a readonly desktop fallback'
if [[ "${REQUIRE_WRITABLE_MOUNT_HANDOFF}" == "1" ]]; then
  grep -q 'mkdir -p "${merged}/proc" "${merged}/sys" "${merged}/dev" "${merged}/run"' "${tmp_dir}/initramfs/init" || fail 'initramfs does not create runtime mount points in the writable live root'
  grep -q 'mount --move /proc "${merged}/proc" || return 1' "${tmp_dir}/initramfs/init" || fail 'initramfs does not require the proc mount handoff'
fi

ssh_runner_shebang="$(
  unsquashfs -cat "${tmp_dir}/auzix-root.squashfs" Services/ssh/run 2>/dev/null |
    head -n 1 || true
)"
if [[ -z "${ssh_runner_shebang}" ]]; then
  # Older/alternate assembly paths may keep an AuzixRoot prefix in the SquashFS.
  ssh_runner_shebang="$(
    unsquashfs -cat "${tmp_dir}/auzix-root.squashfs" AuzixRoot/Services/ssh/run 2>/dev/null |
      head -n 1 || true
  )"
fi
if [[ "${REQUIRE_LIVE_SSH}" == "1" ]]; then
  [[ "${ssh_runner_shebang}" == '#!/Programs/BusyBox/1.36.1/Commands/busybox sh' ]] ||
    fail 'live SSH service runner must use the static BusyBox interpreter directly'
fi

live_scripts=(
  System/Boot/StartSequence \
  Services/udev/run \
  Services/acpid/run \
  System/Tools/start-gui-stage \
  System/Tools/start-e \
  System/Tools/start-enlightenment-session \
  System/Tools/launch-rescue-terminal \
  System/Tools/launch-auzix-browser
)
if [[ "${REQUIRE_LIVE_SSH}" == "1" ]]; then
  live_scripts+=(Services/ssh/run)
fi

for live_script in "${live_scripts[@]}"; do
  shebang="$(unsquashfs -cat "${tmp_dir}/auzix-root.squashfs" "${live_script}" 2>/dev/null | head -n 1 || true)"
  [[ "${shebang}" == '#!/Programs/BusyBox/1.36.1/Commands/busybox sh' ]] ||
    fail "live boot script must use static BusyBox interpreter: /${live_script}"
done

printf 'PASS: boot ISO publication contract: %s\n' "${ISO_PATH}"
