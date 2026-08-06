#!/usr/bin/env bash
set -euo pipefail

# Static publication gate for a bootable AuziX ISO.  This is intentionally
# cheaper than a VM boot: it catches the old BIOS-only artifact and missing
# live-root handoff before an ISO reaches a Proxmox or physical target.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_PATH="${1:-${ROOT_DIR}/artifacts/auzix/auzix-strict-shell.iso}"
REQUIRE_UEFI="${AUZIX_REQUIRE_UEFI:-1}"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "required command missing: $1"; }

need xorriso
need bsdtar
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

grep -q 'console=ttyS0,115200' "${tmp_dir}/grub.cfg" || fail 'serial console boot argument is missing'
mkdir "${tmp_dir}/initramfs"
(cd "${tmp_dir}/initramfs" && gzip -dc "${tmp_dir}/initramfs.cpio.gz" | cpio -idmu 2>/dev/null)
test -f "${tmp_dir}/initramfs/init" || fail 'initramfs /init is missing'
grep -q 'auzix-root.squashfs' "${tmp_dir}/initramfs/init" || fail 'initramfs does not mount the SquashFS root'
grep -q 'refusing readonly desktop fallback' "${tmp_dir}/initramfs/init" || fail 'initramfs permits a readonly desktop fallback'
grep -q 'mkdir -p "${merged}/proc" "${merged}/sys" "${merged}/dev" "${merged}/run"' "${tmp_dir}/initramfs/init" || fail 'initramfs does not create runtime mount points in the writable live root'
grep -q 'mount --move /proc "${merged}/proc" || return 1' "${tmp_dir}/initramfs/init" || fail 'initramfs does not require the proc mount handoff'

printf 'PASS: boot ISO publication contract: %s\n' "${ISO_PATH}"
