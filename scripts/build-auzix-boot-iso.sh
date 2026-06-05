#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STRICT_OUT="${ROOT_DIR}/out/auzix-strict"
DEFAULT_ROOT="${STRICT_OUT}/AuzixRoot"
FALLBACK_ROOT="${STRICT_OUT}/AuzixRoot-pruned"
ROOT_SOURCE="${AUZIX_ROOT_SOURCE:-}"
ARTIFACT_DIR="${ROOT_DIR}/artifacts/auzix"
WORK_DIR="${ROOT_DIR}/out/auzix-iso"
ISO_NAME="${AUZIX_ISO_NAME:-auzix-strict-shell.iso}"
ISO_PATH="${ARTIFACT_DIR}/${ISO_NAME}"
KERNEL_IMAGE="${AUZIX_KERNEL_IMAGE:-}"
KERNEL_RELEASE="${AUZIX_KERNEL_RELEASE:-}"
GRUB_DEFAULT="${AUZIX_GRUB_DEFAULT:-0}"
INCLUDE_LIVE_ASSETS="${AUZIX_INCLUDE_LIVE_ASSETS:-0}"
LIVE_ROOT_MODE="${AUZIX_LIVE_ROOT_MODE:-initramfs}"
INCLUDE_LIVE_NATIVE_MIRRORS="${AUZIX_INCLUDE_LIVE_NATIVE_MIRRORS:-0}"
INCLUDE_ISO_ASSETS="${AUZIX_INCLUDE_ISO_ASSETS:-1}"

log() {
  printf '[auzix-iso] %s\n' "$*" >&2
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

select_kernel() {
  if [[ -n "${KERNEL_IMAGE}" ]]; then
    return
  fi

  local latest=""
  latest="$(find /boot -maxdepth 1 -type f -name 'vmlinuz-*' 2>/dev/null | sort -V | tail -n 1 || true)"
  if [[ -z "${latest}" ]]; then
    printf 'Set AUZIX_KERNEL_IMAGE to a bootable x86_64 kernel image.\n' >&2
    exit 1
  fi
  KERNEL_IMAGE="${latest}"
}

detect_kernel_release() {
  if [[ -n "${KERNEL_RELEASE}" ]]; then
    return
  fi

  case "$(basename "${KERNEL_IMAGE}")" in
    vmlinuz-*)
      KERNEL_RELEASE="$(basename "${KERNEL_IMAGE}")"
      KERNEL_RELEASE="${KERNEL_RELEASE#vmlinuz-}"
      return
      ;;
  esac

  KERNEL_RELEASE="$(file "${KERNEL_IMAGE}" | sed -n 's/.*version \([^ ]*\) .*/\1/p')"
  if [[ -z "${KERNEL_RELEASE}" ]]; then
    printf 'Could not detect kernel release for %s. Set AUZIX_KERNEL_RELEASE.\n' "${KERNEL_IMAGE}" >&2
    exit 1
  fi
}

select_root() {
  if [[ -n "${ROOT_SOURCE}" ]]; then
    return
  fi

  if [[ -d "${DEFAULT_ROOT}" ]]; then
    ROOT_SOURCE="${DEFAULT_ROOT}"
  elif [[ -d "${FALLBACK_ROOT}" ]]; then
    ROOT_SOURCE="${FALLBACK_ROOT}"
  else
    printf 'No Auzix strict root found. Run make auzix-strict-root auzix-strict-busybox first.\n' >&2
    exit 1
  fi
}

write_init() {
  local initramfs_root="$1"
  cat > "${initramfs_root}/init" <<'INIT'
#!/System/Compatibility/bin/sh
export PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
BB=/Programs/BusyBox/1.36.1/Commands/busybox

load_module() {
  local module base module_file rel found
  module="$1"
  base="/System/Drivers/$(uname -r)"
  [ -d "${base}" ] || return 1
  if "${BB}" modprobe -q "${module}" 2>/dev/null; then
    echo "loaded-module=${module}"
    return 0
  fi
  module_file="${module//_/-}.ko"
  rel=""
  if [ -f "${base}/modules.dep" ]; then
    rel="$(grep -m1 "/${module_file}:" "${base}/modules.dep" 2>/dev/null | "${BB}" cut -d: -f1)"
    if [ -z "${rel}" ]; then
      module_file="${module//-/_}.ko"
      rel="$(grep -m1 "/${module_file}:" "${base}/modules.dep" 2>/dev/null | "${BB}" cut -d: -f1)"
    fi
  fi
  if [ -n "${rel}" ]; then
    load_module_path "${base}" "${rel}" "${module}"
    return $?
  fi
  found="$(find "${base}" -type f \( -name "${module}.ko" -o -name "${module}.ko.xz" -o -name "${module}.ko.zst" -o -name "${module//_/-}.ko" -o -name "${module//-/_}.ko" \) 2>/dev/null | head -n 1)"
  [ -n "${found}" ] || return 1
  load_module_file "${found}" "${module}"
}

load_module_path() {
  local base rel label deps dep path module_label
  base="$1"
  rel="$2"
  label="$3"
  path="${base}/${rel}"
  module_label="${label}"
  deps=""
  if [ -f "${base}/modules.dep" ]; then
    deps="$(grep -m1 "^${rel}:" "${base}/modules.dep" 2>/dev/null | "${BB}" cut -d: -f2-)"
  fi
  for dep in ${deps}; do
    load_module_path "${base}" "${dep}" "$("${BB}" basename "${dep}" .ko)" || true
  done
  load_module_file "${path}" "${module_label}"
}

load_module_file() {
  local found label loaded
  found="$1"
  label="$2"
  loaded="/run/auzix-loaded-modules"
  mkdir -p /run
  if grep -qx "${found}" "${loaded}" 2>/dev/null; then
    return 0
  fi
  if "${BB}" insmod "${found}" 2>/dev/null; then
    echo "${found}" >> "${loaded}"
    echo "loaded-module=${label}"
    return 0
  fi
  echo "module-load-failed=${label} path=${found}"
  return 1
}

load_storage_and_net() {
  for module in \
    virtio \
    virtio_ring \
    virtio_pci_legacy_dev \
    virtio_pci_modern_dev \
    virtio_pci \
    virtio_blk \
    scsi_common \
    scsi_mod \
    sd_mod \
    sr_mod \
    virtio_scsi \
    failover \
    net_failover \
    virtio_net \
    libata \
    libahci \
    ata_generic \
    ahci \
    ata_piix \
    pata_acpi \
    pata_oldpiix \
    nvme_core \
    nvme \
    crc16 \
    crc32c_generic \
    crc32c-intel \
    cdrom \
    isofs \
    mbcache \
    jbd2 \
    ext2 \
    ext4 \
    overlay \
    e1000 \
    e1000e \
    pcnet32 \
    vmxnet3 \
    r8169
  do
    load_module "${module}" || true
  done
}

start_dhcp() {
  cat > /run/auzix-udhcpc.script <<'SCRIPT'
#!/System/Compatibility/bin/sh
BB=/Programs/BusyBox/1.36.1/Commands/busybox

case "$1" in
  deconfig)
    "${BB}" ifconfig "${interface}" 0.0.0.0 2>/dev/null || true
    ;;
  bound|renew)
    "${BB}" ifconfig "${interface}" "${ip}" netmask "${subnet}" ${broadcast:+broadcast "${broadcast}"} up
    for route in ${router}; do
      "${BB}" route add default gw "${route}" dev "${interface}" 2>/dev/null || true
    done
    mkdir -p /run
    : > /run/resolv.conf
    for server in ${dns}; do
      echo "nameserver ${server}" >> /run/resolv.conf
    done
    echo "dhcp-lease=${interface} ip=${ip} router=${router} dns=${dns}"
    ;;
esac
SCRIPT
  "${BB}" chmod 0755 /run/auzix-udhcpc.script

  for iface in $(ls /sys/class/net 2>/dev/null); do
    case "${iface}" in
      lo) continue ;;
    esac
    "${BB}" ip link set "${iface}" up 2>/dev/null || true
    "${BB}" udhcpc -i "${iface}" -s /run/auzix-udhcpc.script -t 5 -T 3 -q -b >/System/Logs/udhcpc-"${iface}".log 2>&1 || true
  done
  return 0
}

mount_live_iso_root() {
  local dev iso_root lower merged upper work attempt
  iso_root="/run/auzix-iso"
  lower="${iso_root}/AuzixRoot"
  merged="/run/auzix-root"
  upper="/run/auzix-upper"
  work="/run/auzix-work"

  mkdir -p "${iso_root}" "${merged}"

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    "${BB}" mdev -s 2>/dev/null || true
    for dev in /dev/sr0 /dev/cdrom /dev/disk/by-label/AUZIXLIVE /dev/disk/by-label/ISOIMAGE /dev/hdc /dev/sdb /dev/sda; do
      [ -e "${dev}" ] || continue
      if mount -t iso9660 -o ro "${dev}" "${iso_root}" 2>/dev/null; then
        echo "live-iso=${dev}"
        break 2
      fi
    done
    echo "waiting-for-live-iso attempt=${attempt} block=$(ls /sys/block 2>/dev/null | tr '\n' ' ')"
    "${BB}" sleep 1
  done

  if ! grep -q " ${iso_root} " /proc/mounts 2>/dev/null; then
    echo "Failed to mount Auzix live ISO."
    return 1
  fi
  if [ ! -x "${lower}/System/Boot/StartSequence" ]; then
    echo "AuzixRoot missing from live ISO."
    return 1
  fi

  mkdir -p "${lower}/proc" "${lower}/sys" "${lower}/dev" "${lower}/run" "${upper}" "${work}" 2>/dev/null || true
  if mount -t overlay overlay -o "lowerdir=${lower},upperdir=${upper},workdir=${work}" "${merged}" 2>/dev/null; then
    echo "live-root=overlay lower=${lower} upper=${upper}"
  else
    echo "overlay-root-failed; falling back to readonly bind"
    mount --bind "${lower}" "${merged}" 2>/dev/null || return 1
  fi

  mkdir -p /run/live-run "${merged}/run" 2>/dev/null || true
  mount -t tmpfs tmpfs /run/live-run 2>/dev/null || true
  mount --move /run/live-run "${merged}/run" 2>/dev/null || true

  mkdir -p "${merged}/run/live/iso" 2>/dev/null || true
  mount --move "${iso_root}" "${merged}/run/live/iso" 2>/dev/null || true
  mount --move /proc "${merged}/proc" 2>/dev/null || true
  mount --move /sys "${merged}/sys" 2>/dev/null || true
  mount --move /dev "${merged}/dev" 2>/dev/null || true
  exec "${BB}" switch_root "${merged}" /init
}

mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || mount -t tmpfs tmpfs /dev 2>/dev/null || true
mkdir -p /run /Work/Temp /lib
ln -s /System/Drivers /lib/modules 2>/dev/null || true
[ -e /dev/console ] || mknod /dev/console c 5 1
[ -e /dev/tty0 ] || mknod /dev/tty0 c 4 0
[ -e /dev/tty1 ] || mknod /dev/tty1 c 4 1
[ -e /dev/ttyS0 ] || mknod /dev/ttyS0 c 4 64
exec >/dev/console 2>&1 </dev/console
load_storage_and_net
"${BB}" mdev -s 2>/dev/null || true
echo "block-devices=$(ls /sys/block 2>/dev/null | tr '\n' ' ')"
echo "net-devices=$(ls /sys/class/net 2>/dev/null | tr '\n' ' ')"
start_dhcp

AUZIX_ROOT_DEVICE=""
for arg in $(cat /proc/cmdline 2>/dev/null); do
  case "${arg}" in
    auzix.root=*) AUZIX_ROOT_DEVICE="${arg#auzix.root=}" ;;
  esac
done

if [ -n "${AUZIX_ROOT_DEVICE}" ]; then
  echo "Auzix requested installed root: ${AUZIX_ROOT_DEVICE}"
  mkdir -p /run/auzix-root
  if mount "${AUZIX_ROOT_DEVICE}" /run/auzix-root; then
    mount --move /proc /run/auzix-root/proc 2>/dev/null || true
    mount --move /sys /run/auzix-root/sys 2>/dev/null || true
    mount --move /dev /run/auzix-root/dev 2>/dev/null || true
    exec "${BB}" switch_root /run/auzix-root /init
  fi
  echo "Failed to mount requested Auzix root: ${AUZIX_ROOT_DEVICE}"
fi

mount_live_iso_root || true

clear 2>/dev/null || true
if [ -x /System/Boot/StartSequence ]; then
  /System/Boot/StartSequence
fi

echo "Auzix strict-root live shell"
echo "root-contract=/System /Programs /Services /Stacks /Work /Users /Volumes /Network"
echo "kernel=$(uname -r)"
echo "console=/dev/console"
echo "installer=/System/Tools/auzix-install-disk"
echo "network=best-effort-udhcpc"
echo "startup=/System/Boot/StartSequence"
echo "gui=/System/Tools/start-gui-stage"
echo

if [ -c /dev/tty1 ]; then
  "${BB}" setsid "${BB}" sh -c 'echo "Auzix console shell. Run /System/Tools/start-gui-stage for desktop." >/dev/tty1; exec /Programs/BusyBox/1.36.1/Commands/busybox sh </dev/tty1 >/dev/tty1 2>&1' &
fi

if [ -c /dev/ttyS0 ]; then
  "${BB}" setsid "${BB}" sh -c 'exec /Programs/BusyBox/1.36.1/Commands/busybox sh </dev/ttyS0 >/dev/ttyS0 2>&1' &
fi

if [ -e /System/Settings/display/autostart ]; then
  exec "${BB}" sh -c 'while true; do sleep 3600; done'
fi

exec "${BB}" cttyhack "${BB}" sh
INIT
  chmod 0755 "${initramfs_root}/init"
}

write_grub_cfg() {
  local iso_root="$1"
  cat > "${iso_root}/boot/grub/grub.cfg" <<GRUB
set timeout=3
set default=${GRUB_DEFAULT}

menuentry "Auzix strict-root shell" {
    linux /boot/vmlinuz console=ttyS0,115200 console=tty0
    initrd /boot/initramfs.cpio.gz
}

menuentry "Auzix installed root (/dev/sda1)" {
    linux /boot/vmlinuz console=ttyS0,115200 console=tty0 auzix.root=/dev/sda1
    initrd /boot/initramfs.cpio.gz
}
GRUB
}

need_cmd cpio
need_cmd file
need_cmd gzip
need_cmd grub-mkrescue
select_kernel
select_root
detect_kernel_release

if [[ ! -f "${KERNEL_IMAGE}" ]]; then
  printf 'Kernel image not found: %s\n' "${KERNEL_IMAGE}" >&2
  exit 1
fi
if [[ ! -x "${ROOT_SOURCE}/Programs/BusyBox/1.36.1/Commands/busybox" ]]; then
  printf 'BusyBox payload missing from %s. Run make auzix-strict-busybox first.\n' "${ROOT_SOURCE}" >&2
  exit 1
fi

log "Using root: ${ROOT_SOURCE}"
log "Using kernel: ${KERNEL_IMAGE} (${KERNEL_RELEASE})"

if [[ ! -d "${ROOT_SOURCE}/System/Drivers/${KERNEL_RELEASE}" ]]; then
  if [[ -d "/lib/modules/${KERNEL_RELEASE}" ]]; then
    log "Packaging modules for selected kernel into ${ROOT_SOURCE}"
    AUZIX_KERNEL_RELEASE="${KERNEL_RELEASE}" "${ROOT_DIR}/scripts/package-auzix-kernel-modules.sh" "${ROOT_SOURCE}"
  else
    printf 'Missing matching modules for %s.\n' "${KERNEL_RELEASE}" >&2
    printf 'Expected %s/System/Drivers/%s or /lib/modules/%s.\n' "${ROOT_SOURCE}" "${KERNEL_RELEASE}" "${KERNEL_RELEASE}" >&2
    exit 1
  fi
fi

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}/initramfs" "${WORK_DIR}/iso/boot/grub" "${ARTIFACT_DIR}"

case "${LIVE_ROOT_MODE}" in
  initramfs)
    log "Using whole-root initramfs live mode"
    cp -a "${ROOT_SOURCE}/." "${WORK_DIR}/initramfs/"
    if [[ "${INCLUDE_LIVE_NATIVE_MIRRORS}" != "1" ]]; then
      rm -rf \
        "${WORK_DIR}/initramfs/System/Drivers/Xorg" \
        "${WORK_DIR}/initramfs/System/Fonts" \
        "${WORK_DIR}/initramfs/System/Settings/X11/xkb"
    fi
    if [[ "${INCLUDE_LIVE_ASSETS}" != "1" ]]; then
      rm -rf "${WORK_DIR}/initramfs/System/Settings/display/assets"
      mkdir -p "${WORK_DIR}/initramfs/System/Settings/display/assets"
      cat > "${WORK_DIR}/initramfs/System/Settings/display/assets/README.txt" <<'EOF'
Large Enlightenment assets are intentionally not embedded in the live initramfs.
Stage them onto an installed root or package store with stage-auzix-enlightenment-assets.sh.
Set AUZIX_INCLUDE_LIVE_ASSETS=1 only for media where a large boot payload is acceptable.
EOF
    fi
    ;;
  iso-root)
    log "Using split ISO-root live mode"
    mkdir -p "${WORK_DIR}/iso/AuzixRoot"
    mkdir -p \
      "${WORK_DIR}/initramfs/bin" \
      "${WORK_DIR}/initramfs/Programs" \
      "${WORK_DIR}/initramfs/System/Compatibility/bin" \
      "${WORK_DIR}/initramfs/System/Drivers" \
      "${WORK_DIR}/initramfs/System/Logs" \
      "${WORK_DIR}/initramfs/Work/Temp" \
      "${WORK_DIR}/initramfs/proc" \
      "${WORK_DIR}/initramfs/sys" \
      "${WORK_DIR}/initramfs/dev" \
      "${WORK_DIR}/initramfs/run"
    cp -a "${ROOT_SOURCE}/Programs/BusyBox" "${WORK_DIR}/initramfs/Programs/"
    cp -a "${ROOT_SOURCE}/System/Drivers/${KERNEL_RELEASE}" "${WORK_DIR}/initramfs/System/Drivers/"
    ln -sfn /Programs/BusyBox/1.36.1/Commands/busybox "${WORK_DIR}/initramfs/System/Compatibility/bin/sh"
    for applet in basename cat clear cp cttyhack cut echo find grep head ifconfig insmod ip ln ls mkdir mknod modprobe mount mountpoint route sed setsid sh sleep switch_root tr udhcpc uname; do
      ln -sfn /Programs/BusyBox/1.36.1/Commands/busybox "${WORK_DIR}/initramfs/System/Compatibility/bin/${applet}"
      ln -sfn /Programs/BusyBox/1.36.1/Commands/busybox "${WORK_DIR}/initramfs/bin/${applet}"
    done
    cp -a "${ROOT_SOURCE}/." "${WORK_DIR}/iso/AuzixRoot/"
    if [[ "${INCLUDE_LIVE_ASSETS}" != "1" ]]; then
      rm -rf "${WORK_DIR}/iso/AuzixRoot/System/Settings/display/assets"
      mkdir -p "${WORK_DIR}/iso/AuzixRoot/System/Settings/display/assets"
      cat > "${WORK_DIR}/iso/AuzixRoot/System/Settings/display/assets/README.txt" <<'EOF'
Large Enlightenment assets are intentionally not embedded in the live ISO root.
Stage them onto an installed root or package store with stage-auzix-enlightenment-assets.sh.
Set AUZIX_INCLUDE_LIVE_ASSETS=1 only for media where a large ISO payload is acceptable.
EOF
    fi
    ;;
  *)
    printf 'Unknown AUZIX_LIVE_ROOT_MODE=%s. Use initramfs or iso-root.\n' "${LIVE_ROOT_MODE}" >&2
    exit 1
    ;;
esac
write_init "${WORK_DIR}/initramfs"

(
  cd "${WORK_DIR}/initramfs"
  find . -print0 | cpio --null -o --format=newc --owner=0:0 2>/dev/null | gzip -9 > "${WORK_DIR}/iso/boot/initramfs.cpio.gz"
)

cp "${KERNEL_IMAGE}" "${WORK_DIR}/iso/boot/vmlinuz"
if [[ "${INCLUDE_ISO_ASSETS}" == "1" && -d "${ROOT_SOURCE}/System/Settings/display/assets" ]]; then
  mkdir -p "${WORK_DIR}/iso/live/assets"
  printf 'auzix live media\n' > "${WORK_DIR}/iso/live/AUZIXLIVE"
  cp -a "${ROOT_SOURCE}/System/Settings/display/assets/." "${WORK_DIR}/iso/live/assets/"
fi
write_grub_cfg "${WORK_DIR}/iso"

grub-mkrescue -o "${ISO_PATH}" "${WORK_DIR}/iso" >/dev/null

sha256sum "${ISO_PATH}" > "${ISO_PATH}.sha256"
ls -lh "${ISO_PATH}" "${ISO_PATH}.sha256"
log "Boot ISO ready: ${ISO_PATH}"
