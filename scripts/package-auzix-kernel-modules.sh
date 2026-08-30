#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
if [[ -n "${AUZIX_KERNEL_RELEASE:-}" ]]; then
  KERNEL_RELEASE="${AUZIX_KERNEL_RELEASE}"
else
  KERNEL_RELEASE="$(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -n 1)"
  KERNEL_RELEASE="${KERNEL_RELEASE:-$(uname -r)}"
fi
HOST_MODULE_DIR="/lib/modules/${KERNEL_RELEASE}"
TARGET_MODULE_DIR="${AUZIX_ROOT}/System/Drivers/${KERNEL_RELEASE}"
INCLUDE_GRAPHICS="${AUZIX_INCLUDE_GRAPHICS_MODULES:-1}"
INCLUDE_AUDIO="${AUZIX_INCLUDE_AUDIO_MODULES:-0}"
INCLUDE_CONTAINER_HOST="${AUZIX_INCLUDE_CONTAINER_HOST_MODULES:-1}"
declare -A COPIED_MODULES=()
declare -A COPIED_PATHS=()

log() {
  printf '[auzix-modules] %s\n' "$*" >&2
}

module_present_in_target() {
  local module="$1"
  find "${TARGET_MODULE_DIR}" -type f \( \
    -name "${module}.ko" -o \
    -name "${module}.ko.xz" -o \
    -name "${module}.ko.zst" -o \
    -name "${module}.ko.gz" \
  \) -print -quit | grep -q .
}

module_builtin_on_host() {
  local module="$1"
  local mod_dash="${module//_/-}"
  local mod_under="${module//-/_}"
  [[ -f "${HOST_MODULE_DIR}/modules.builtin" ]] || return 1
  grep -Eq "(^|/)(${mod_dash}|${mod_under})\\.ko($|[[:space:]])" "${HOST_MODULE_DIR}/modules.builtin"
}

required_module_available() {
  local module="$1"
  module_present_in_target "${module}" || module_builtin_on_host "${module}"
}

module_name_from_dep_path() {
  local dep_path="$1"
  dep_path="$(basename "${dep_path}")"
  dep_path="${dep_path%.xz}"
  dep_path="${dep_path%.zst}"
  dep_path="${dep_path%.gz}"
  dep_path="${dep_path%.ko}"
  printf '%s\n' "${dep_path}"
}

copy_module_path() {
  local rel="$1"
  local src="${HOST_MODULE_DIR}/${rel}"
  if [[ ! -f "${src}" ]]; then
    log "Skipping missing module ${rel}"
    return 0
  fi
  if [[ -n "${COPIED_PATHS[${rel}]:-}" ]]; then
    return 0
  fi
  COPIED_PATHS["${rel}"]=1
  mkdir -p "${TARGET_MODULE_DIR}/$(dirname "${rel}")"
  cp -a "${src}" "${TARGET_MODULE_DIR}/${rel}"
}

copy_module_name() {
  local module="$1"
  local filename rel dep depends dep_path dep_module dep_line module_file

  if [[ -n "${COPIED_MODULES[${module}]:-}" ]]; then
    return 0
  fi
  COPIED_MODULES["${module}"]=1

  filename=""
  if command -v modinfo >/dev/null 2>&1; then
    filename="$(modinfo -k "${KERNEL_RELEASE}" -F filename "${module}" 2>/dev/null || true)"
  fi
  if [[ -z "${filename}" && -f "${HOST_MODULE_DIR}/modules.dep" ]]; then
    module_file="${module//_/-}.ko"
    dep_line="$(grep -m1 "/${module_file}:" "${HOST_MODULE_DIR}/modules.dep" 2>/dev/null || true)"
    if [[ -z "${dep_line}" ]]; then
      module_file="${module//-/_}.ko"
      dep_line="$(grep -m1 "/${module_file}:" "${HOST_MODULE_DIR}/modules.dep" 2>/dev/null || true)"
    fi
    if [[ -n "${dep_line}" ]]; then
      rel="${dep_line%%:*}"
      filename="${HOST_MODULE_DIR}/${rel}"
    fi
  fi
  if [[ -z "${filename}" ]]; then
    log "Skipping unavailable/built-in module ${module}"
    return 0
  fi
  if [[ "${filename}" != "${HOST_MODULE_DIR}/"* ]]; then
    log "Skipping module outside ${HOST_MODULE_DIR}: ${filename}"
    return 0
  fi

  rel="${filename#${HOST_MODULE_DIR}/}"
  if [[ -f "${HOST_MODULE_DIR}/modules.dep" ]]; then
    dep_line="$(grep -m1 "^${rel}:" "${HOST_MODULE_DIR}/modules.dep" 2>/dev/null || true)"
    if [[ -n "${dep_line}" ]]; then
      for dep_path in ${dep_line#*:}; do
        [[ -z "${dep_path}" ]] && continue
        dep_module="$(module_name_from_dep_path "${dep_path}")"
        copy_module_name "${dep_module}"
      done
    fi
  elif command -v modinfo >/dev/null 2>&1; then
    depends="$(modinfo -k "${KERNEL_RELEASE}" -F depends "${module}" 2>/dev/null || true)"
    IFS=',' read -ra deps <<< "${depends}"
    for dep in "${deps[@]}"; do
      [[ -z "${dep}" ]] && continue
      copy_module_name "${dep}"
    done
  fi

  mkdir -p "${TARGET_MODULE_DIR}/$(dirname "${rel}")"
  cp -a "${filename}" "${TARGET_MODULE_DIR}/${rel}"
  COPIED_PATHS["${rel}"]=1
}

if [[ ! -d "${HOST_MODULE_DIR}" ]]; then
  printf 'Host module directory not found: %s\n' "${HOST_MODULE_DIR}" >&2
  exit 1
fi
if [[ ! -f "${HOST_MODULE_DIR}/modules.dep" ]]; then
  printf 'Kernel module index is missing: %s/modules.dep\n' "${HOST_MODULE_DIR}" >&2
  printf 'Install the matching kernel package normally or run depmod before packaging modules.\n' >&2
  exit 1
fi
if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

mkdir -p "${TARGET_MODULE_DIR}"

module_names=(
  virtio
  virtio_ring
  virtio_pci
  virtio_pci_legacy_dev
  virtio_pci_modern_dev
  virtio_blk
  virtio_scsi
  virtio_net
  failover
  net_failover
  scsi_common
  scsi_mod
  sd_mod
  sr_mod
  libata
  libahci
  ata_generic
  ahci
  ata_piix
  pata_acpi
  pata_oldpiix
  nvme
  nvme_core
  e1000
  e1000e
  pcnet32
  vmxnet3
  r8169
  cdrom
  loop
  isofs
  squashfs
  crc16
  crc32c_generic
  crc32c-intel
  ext2
  ext4
  overlay
  jbd2
  mbcache
)

graphics_module_names=(
  drm
  drm_kms_helper
  drm_display_helper
  drm_vram_helper
  drm_ttm_helper
  drm_shmem_helper
  ttm
  bochs
  qxl
  vmwgfx
  virtio-gpu
  virtio_dma_buf
  evdev
  joydev
  psmouse
  hid
  hid-generic
  usbhid
  usb-common
  usbcore
  ehci-hcd
  ehci-pci
  uhci-hcd
  ohci-hcd
  ohci-pci
  xhci-hcd
  xhci-pci
)

audio_module_names=(
  ledtrig-audio
  soundcore
  snd
  snd-hwdep
  snd-timer
  snd-pcm
  snd-hda-core
  snd-hda-codec
  snd-hda-codec-generic
  snd-hda-intel
)

container_host_module_names=(
  bridge
  br_netfilter
  veth
  tun
  fuse
  cuse
  virtiofs
  nfnetlink
  nf_tables
  nft_chain_nat
  nft_compat
  nft_counter
  nft_ct
  nf_conntrack
  nf_defrag_ipv4
  nf_nat
  x_tables
  ip_tables
  iptable_filter
  iptable_nat
  xt_MASQUERADE
  xt_addrtype
  xt_comment
  xt_conntrack
)

for module in "${module_names[@]}"; do
  copy_module_name "${module}"
done

# Live media cannot operate without these exact filesystem modules.  Do not
# publish a superficially successful receipt that silently omitted one.
for required_live_module in loop isofs squashfs overlay; do
  if ! required_module_available "${required_live_module}"; then
    printf 'Required live-boot module was not packaged: %s\n' "${required_live_module}" >&2
    exit 1
  fi
done
if [[ "${INCLUDE_GRAPHICS}" == "1" ]]; then
  for module in "${graphics_module_names[@]}"; do
    copy_module_name "${module}"
  done
fi
if [[ "${INCLUDE_AUDIO}" == "1" ]]; then
  for module in "${audio_module_names[@]}"; do
    copy_module_name "${module}"
  done
fi
if [[ "${INCLUDE_CONTAINER_HOST}" == "1" ]]; then
  for module in "${container_host_module_names[@]}"; do
    copy_module_name "${module}"
  done
  for required_container_module in bridge veth nf_tables; do
    if ! required_module_available "${required_container_module}"; then
      printf 'Required container-host module was not packaged: %s\n' "${required_container_module}" >&2
      exit 1
    fi
  done
  # Flatpak's document portal and many developer desktop tools require a real
  # kernel FUSE mount at /run/user/<uid>/doc.  A package that preserves
  # modules.dep but drops kernel/fs/fuse/fuse.ko creates a convincing-looking
  # but broken desktop, so fail here while the build still has the source tree.
  for required_fuse_module in fuse; do
    if ! required_module_available "${required_fuse_module}"; then
      printf 'Required desktop/container FUSE module was not packaged: %s\n' "${required_fuse_module}" >&2
      exit 1
    fi
  done
fi

# Keep a few historical exact paths as a fallback for kernels where aliases
# differ from the source tree's module filename.
for module in \
  kernel/drivers/virtio/virtio.ko \
  kernel/drivers/virtio/virtio_ring.ko \
  kernel/drivers/virtio/virtio_pci.ko \
  kernel/drivers/block/virtio_blk.ko \
  kernel/drivers/net/virtio_net.ko \
  kernel/drivers/gpu/drm/vmwgfx/vmwgfx.ko
do
  copy_module_path "${module}"
done

cp -a "${HOST_MODULE_DIR}/modules.order" "${TARGET_MODULE_DIR}/modules.order" 2>/dev/null || true
cp -a "${HOST_MODULE_DIR}/modules.dep" "${TARGET_MODULE_DIR}/modules.dep" 2>/dev/null || true
cp -a "${HOST_MODULE_DIR}/modules.dep.bin" "${TARGET_MODULE_DIR}/modules.dep.bin" 2>/dev/null || true
cp -a "${HOST_MODULE_DIR}/modules.alias" "${TARGET_MODULE_DIR}/modules.alias" 2>/dev/null || true
cp -a "${HOST_MODULE_DIR}/modules.alias.bin" "${TARGET_MODULE_DIR}/modules.alias.bin" 2>/dev/null || true
cp -a "${HOST_MODULE_DIR}/modules.builtin" "${TARGET_MODULE_DIR}/modules.builtin" 2>/dev/null || true
cp -a "${HOST_MODULE_DIR}/modules.builtin.modinfo" "${TARGET_MODULE_DIR}/modules.builtin.modinfo" 2>/dev/null || true

cat > "${AUZIX_ROOT}/System/PackageDB/KernelModules-${KERNEL_RELEASE}.auzix.json" <<JSON
{
  "name": "KernelModules",
  "version": "${KERNEL_RELEASE}",
  "kind": "system",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/System/Drivers/${KERNEL_RELEASE}",
  "notes": "Minimal host kernel modules needed for VM disk, network, ISO, ext filesystems, and the rootful container-host bridge. Optional early DRM/input and Intel HDA audio modules are gated separately."
}
JSON

log "Packaged modules into ${TARGET_MODULE_DIR}"
log "Module gates: graphics=${INCLUDE_GRAPHICS} audio=${INCLUDE_AUDIO} container_host=${INCLUDE_CONTAINER_HOST}"
