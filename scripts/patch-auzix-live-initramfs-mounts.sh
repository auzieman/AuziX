#!/usr/bin/env bash
set -euo pipefail

SOURCE_ISO="${1:?usage: $0 SOURCE_ISO OUTPUT_ISO}"
OUTPUT_ISO="${2:?usage: $0 SOURCE_ISO OUTPUT_ISO}"

for command in xorriso gzip cpio sha256sum; do
  command -v "${command}" >/dev/null 2>&1 || {
    printf 'required command missing: %s\n' "${command}" >&2
    exit 1
  }
done
[[ -f "${SOURCE_ISO}" ]] || { printf 'source ISO missing: %s\n' "${SOURCE_ISO}" >&2; exit 1; }
[[ ! -e "${OUTPUT_ISO}" ]] || { printf 'output already exists: %s\n' "${OUTPUT_ISO}" >&2; exit 1; }

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
mkdir -p "${work_dir}/initramfs"

xorriso -osirrox on -indev "${SOURCE_ISO}" \
  -extract /boot/initramfs.cpio.gz "${work_dir}/initramfs.cpio.gz" >/dev/null 2>&1
(cd "${work_dir}/initramfs" && gzip -dc ../initramfs.cpio.gz | cpio -idmu --quiet)

init_file="${work_dir}/initramfs/init"
[[ -f "${init_file}" ]] || { printf 'initramfs /init missing\n' >&2; exit 1; }
grep -Fq 'mkdir -p "${lower}/proc" "${lower}/sys" "${lower}/dev" "${lower}/run" "${upper}" "${work}"' "${init_file}" || {
  printf 'source initramfs does not contain the expected broken mount-point handoff\n' >&2
  exit 1
}

sed -i \
  's@mkdir -p "${lower}/proc" "${lower}/sys" "${lower}/dev" "${lower}/run" "${upper}" "${work}" 2>/dev/null || true@mkdir -p "${upper}" "${work}"@' \
  "${init_file}"
sed -i \
  '/echo "Auzix live overlay root failed; refusing readonly desktop fallback."/,/fi/!b; /fi/a\
\
  mkdir -p "${merged}/proc" "${merged}/sys" "${merged}/dev" "${merged}/run"' \
  "${init_file}"
sed -i \
  -e 's@mount --move /proc "${merged}/proc" 2>/dev/null || true@mount --move /proc "${merged}/proc" || return 1@' \
  -e 's@mount --move /sys "${merged}/sys" 2>/dev/null || true@mount --move /sys "${merged}/sys" || return 1@' \
  -e 's@mount --move /dev "${merged}/dev" 2>/dev/null || true@mount --move /dev "${merged}/dev" || return 1@' \
  "${init_file}"

grep -Fq 'mkdir -p "${merged}/proc" "${merged}/sys" "${merged}/dev" "${merged}/run"' "${init_file}"
grep -Fq 'mount --move /proc "${merged}/proc" || return 1' "${init_file}"

(cd "${work_dir}/initramfs" && find . -print0 | sort -z | cpio --null -o -H newc --quiet | gzip -n -9 >"${work_dir}/patched.cpio.gz")

xorriso -indev "${SOURCE_ISO}" -outdev "${OUTPUT_ISO}" \
  -boot_image any replay \
  -map "${work_dir}/patched.cpio.gz" /boot/initramfs.cpio.gz \
  -commit >/dev/null 2>&1

sha256sum "${OUTPUT_ISO}" >"${OUTPUT_ISO}.sha256"
printf 'patched ISO: %s\n' "${OUTPUT_ISO}"
