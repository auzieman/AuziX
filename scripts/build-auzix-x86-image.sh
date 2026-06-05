#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${ROOT_DIR}/artifacts/auzix"
BUILD_DIR="${ROOT_DIR}/out/auzix-build"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
MNT_DIR="${BUILD_DIR}/mnt"
IMAGE_NAME="${AUZIX_IMAGE_NAME:-auzix}"
RAW_IMAGE_PATH="${ARTIFACT_DIR}/${IMAGE_NAME}.raw"
QCOW2_IMAGE_PATH="${ARTIFACT_DIR}/${IMAGE_NAME}.qcow2"
PACKAGE_PROFILE="${1:-${ROOT_DIR}/profiles/rootfs/auzix-thin-desktop.debian-packages}"
SUITE="${AUZIX_SUITE:-bookworm}"
MIRROR="${AUZIX_MIRROR:-http://deb.debian.org/debian}"
IMAGE_SIZE_GB="${AUZIX_IMAGE_SIZE_GB:-16}"
WORK_SIZE_GB="${AUZIX_WORK_SIZE_GB:-4}"
BOOT_TARGET="${AUZIX_BOOT_TARGET:-multi-user.target}"
HOSTNAME="${AUZIX_HOSTNAME:-auzix}"
USERNAME="${AUZIX_USERNAME:-auzi}"
USER_PASSWORD="${AUZIX_PASSWORD:-auzi}"
ROOT_PASSWORD="${AUZIX_ROOT_PASSWORD:-root}"
ROOT_LABEL="AUZIXROOT"
WORK_LABEL="AUZIXWORK"
ROOT_UUID=""
WORK_UUID=""
LOOPDEV=""
REQUIRED_PACKAGES=(
  systemd-sysv
  linux-image-amd64
  grub-pc
  initramfs-tools
  sudo
  locales
  dbus
)

log() {
  printf '[auzix-build] %s\n' "$*" >&2
}

require_file() {
  local path="$1"
  local message="$2"

  if [[ ! -e "${path}" ]]; then
    printf '%s\n' "${message}" >&2
    exit 1
  fi
}

cleanup() {
  set +e

  if mountpoint -q "${ROOTFS_DIR}/dev/pts"; then umount -lf "${ROOTFS_DIR}/dev/pts"; fi
  if mountpoint -q "${ROOTFS_DIR}/dev"; then umount -lf "${ROOTFS_DIR}/dev"; fi
  if mountpoint -q "${ROOTFS_DIR}/proc"; then umount -lf "${ROOTFS_DIR}/proc"; fi
  if mountpoint -q "${ROOTFS_DIR}/sys"; then umount -lf "${ROOTFS_DIR}/sys"; fi
  if mountpoint -q "${ROOTFS_DIR}/run"; then umount -lf "${ROOTFS_DIR}/run"; fi
  if mountpoint -q "${ROOTFS_DIR}/work"; then umount -lf "${ROOTFS_DIR}/work"; fi
  if mountpoint -q "${ROOTFS_DIR}"; then umount -lf "${ROOTFS_DIR}"; fi

  if [[ -n "${LOOPDEV}" ]]; then
    losetup -d "${LOOPDEV}" 2>/dev/null || true
  fi
}

detach_stale_loopdevs() {
  local stale_loopdev

  while IFS= read -r stale_loopdev; do
    [[ -z "${stale_loopdev}" ]] && continue
    losetup -d "${stale_loopdev}" 2>/dev/null || true
  done < <(losetup -j "${RAW_IMAGE_PATH}" | cut -d: -f1)
}

reset_workspace_mounts() {
  local path

  for path in \
    "${ROOTFS_DIR}/dev/pts" \
    "${ROOTFS_DIR}/dev" \
    "${ROOTFS_DIR}/proc" \
    "${ROOTFS_DIR}/sys" \
    "${ROOTFS_DIR}/run" \
    "${ROOTFS_DIR}/work" \
    "${ROOTFS_DIR}"
  do
    if mountpoint -q "${path}"; then
      umount -lf "${path}"
    fi
  done

  detach_stale_loopdevs
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
  fi
}

require_commands() {
  local missing=()
  local cmd

  for cmd in debootstrap parted losetup mkfs.ext4 blkid rsync chroot grub-install update-initramfs update-grub qemu-img; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      missing+=("${cmd}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'Missing required commands: %s\n' "${missing[*]}" >&2
    exit 1
  fi
}

resolve_package_profile() {
  if [[ ! -f "${PACKAGE_PROFILE}" ]]; then
    printf 'Package profile not found: %s\n' "${PACKAGE_PROFILE}" >&2
    exit 1
  fi
}

prepare_dirs() {
  reset_workspace_mounts
  mkdir -p "${ARTIFACT_DIR}" "${BUILD_DIR}" "${ROOTFS_DIR}" "${MNT_DIR}"
  rm -rf "${ROOTFS_DIR:?}"/*
}

create_image() {
  local root_end_gb

  if (( WORK_SIZE_GB >= IMAGE_SIZE_GB )); then
    printf 'AUZIX_WORK_SIZE_GB must be smaller than AUZIX_IMAGE_SIZE_GB.\n' >&2
    exit 1
  fi

  root_end_gb=$((IMAGE_SIZE_GB - WORK_SIZE_GB))

  log "Creating sparse raw image at ${RAW_IMAGE_PATH}"
  rm -f "${RAW_IMAGE_PATH}" "${QCOW2_IMAGE_PATH}"
  truncate -s "${IMAGE_SIZE_GB}G" "${RAW_IMAGE_PATH}"

  parted -s "${RAW_IMAGE_PATH}" mklabel msdos
  parted -s "${RAW_IMAGE_PATH}" unit MiB mkpart primary ext4 1 "$((root_end_gb * 1024))"
  parted -s "${RAW_IMAGE_PATH}" set 1 boot on
  parted -s "${RAW_IMAGE_PATH}" unit MiB mkpart primary ext4 "$((root_end_gb * 1024))" 100%

  LOOPDEV="$(losetup --show -Pf "${RAW_IMAGE_PATH}")"
  log "Loop device: ${LOOPDEV}"

  mkfs.ext4 -F -L "${ROOT_LABEL}" "${LOOPDEV}p1" >/dev/null
  mkfs.ext4 -F -L "${WORK_LABEL}" "${LOOPDEV}p2" >/dev/null

  ROOT_UUID="$(blkid -s UUID -o value "${LOOPDEV}p1")"
  WORK_UUID="$(blkid -s UUID -o value "${LOOPDEV}p2")"
}

mount_image() {
  mount "${LOOPDEV}p1" "${ROOTFS_DIR}"
  mkdir -p "${ROOTFS_DIR}/work"
  mount "${LOOPDEV}p2" "${ROOTFS_DIR}/work"
  mkdir -p "${ROOTFS_DIR}/work/home" "${ROOTFS_DIR}/work/state" "${ROOTFS_DIR}/work/log" "${ROOTFS_DIR}/work/cache" "${ROOTFS_DIR}/work/env" "${ROOTFS_DIR}/work/root"
}

bootstrap_base_system() {
  log "Bootstrapping Debian ${SUITE}"
  debootstrap --arch=amd64 --variant=minbase "${SUITE}" "${ROOTFS_DIR}" "${MIRROR}"

  cat > "${ROOTFS_DIR}/etc/apt/sources.list" <<EOF
deb ${MIRROR} ${SUITE} main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${SUITE}-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${SUITE}-updates main contrib non-free non-free-firmware
EOF

  cat > "${ROOTFS_DIR}/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
exit 101
EOF
  chmod +x "${ROOTFS_DIR}/usr/sbin/policy-rc.d"

  cp /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"
  mount --rbind /dev "${ROOTFS_DIR}/dev"
  mount -t proc proc "${ROOTFS_DIR}/proc"
  mount -t sysfs sys "${ROOTFS_DIR}/sys"
  mount --rbind /run "${ROOTFS_DIR}/run"
}

filter_package_profile() {
  local filtered="${BUILD_DIR}/packages.filtered"
  : > "${filtered}"

  while IFS= read -r pkg; do
    [[ -z "${pkg}" || "${pkg}" == \#* ]] && continue

    if chroot "${ROOTFS_DIR}" bash -lc "apt-cache show '${pkg}' >/dev/null 2>&1"; then
      printf '%s\n' "${pkg}" >> "${filtered}"
    else
      log "Skipping unavailable package: ${pkg}"
    fi
  done < "${PACKAGE_PROFILE}"

  printf '%s\n' "${filtered}"
}

install_packages() {
  local filtered
  local package_args=("${REQUIRED_PACKAGES[@]}")

  chroot "${ROOTFS_DIR}" env DEBIAN_FRONTEND=noninteractive apt-get update
  chroot "${ROOTFS_DIR}" bash -lc "printf '%s\n' \
    'grub-pc grub-pc/install_devices_empty boolean true' \
    'grub-pc grub-pc/install_devices multiselect' | debconf-set-selections"
  filtered="$(filter_package_profile)"
  mapfile -t filtered_packages < "${filtered}"
  package_args+=("${filtered_packages[@]}")

  log "Installing package set into chroot"
  chroot "${ROOTFS_DIR}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "${package_args[@]}"
}

configure_system() {
  log "Configuring Auzix skeleton and first-pass overrides"

  chroot "${ROOTFS_DIR}" bash -lc "echo 'root:${ROOT_PASSWORD}' | chpasswd"
  chroot "${ROOTFS_DIR}" bash -lc "id -u '${USERNAME}' >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo '${USERNAME}'"
  chroot "${ROOTFS_DIR}" bash -lc "echo '${USERNAME}:${USER_PASSWORD}' | chpasswd"

  cat > "${ROOTFS_DIR}/etc/hostname" <<EOF
${HOSTNAME}
EOF

  cat > "${ROOTFS_DIR}/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 ${HOSTNAME}

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

  cat > "${ROOTFS_DIR}/etc/fstab" <<EOF
UUID=${ROOT_UUID} / ext4 defaults 0 1
UUID=${WORK_UUID} /work ext4 defaults 0 2
tmpfs /ram tmpfs nosuid,nodev,mode=0755 0 0
EOF

  mkdir -p \
    "${ROOTFS_DIR}/system/c" \
    "${ROOTFS_DIR}/system/libs" \
    "${ROOTFS_DIR}/system/s" \
    "${ROOTFS_DIR}/system/devs" \
    "${ROOTFS_DIR}/system/prefs" \
    "${ROOTFS_DIR}/system/apps" \
    "${ROOTFS_DIR}/system/docs" \
    "${ROOTFS_DIR}/ram"

  mkdir -p "${ROOTFS_DIR}/work/home" "${ROOTFS_DIR}/work/state" "${ROOTFS_DIR}/work/log" "${ROOTFS_DIR}/work/cache" "${ROOTFS_DIR}/work/env" "${ROOTFS_DIR}/work/root"

  rm -rf "${ROOTFS_DIR}/home" "${ROOTFS_DIR}/tmp"
  ln -s /work/home "${ROOTFS_DIR}/home"
  ln -s /ram/tmp "${ROOTFS_DIR}/tmp"

  cat > "${ROOTFS_DIR}/etc/profile.d/auzix-env.sh" <<'EOF'
export AUZIX_SYSTEM=/system
export AUZIX_WORK=/work
export AUZIX_RAM=/ram
export PATH=/system/c:${PATH}
export LD_LIBRARY_PATH=/system/libs${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export TMPDIR=/ram/tmp
export XDG_CACHE_HOME=${HOME}/.cache
export XDG_CONFIG_HOME=${HOME}/.config
export XDG_DATA_HOME=${HOME}/.local/share
EOF

  cat > "${ROOTFS_DIR}/system/c/start-gui" <<'EOF'
#!/bin/sh
exec systemctl isolate graphical.target
EOF
  chmod +x "${ROOTFS_DIR}/system/c/start-gui"

  cat > "${ROOTFS_DIR}/system/c/auzix-report" <<'EOF'
#!/bin/sh
echo "Auzix path report"
echo "================="
printf 'PATH=%s\n' "$PATH"
printf 'LD_LIBRARY_PATH=%s\n' "${LD_LIBRARY_PATH:-}"
printf 'HOME=%s\n' "$HOME"
printf 'TMPDIR=%s\n' "${TMPDIR:-}"
mount | egrep ' on /(work|ram) '
EOF
  chmod +x "${ROOTFS_DIR}/system/c/auzix-report"

  cat > "${ROOTFS_DIR}/etc/tmpfiles.d/auzix.conf" <<'EOF'
d /ram/tmp 1777 root root -
d /ram/env 0755 root root -
d /work/home 0755 root root -
d /work/state 0755 root root -
d /work/log 0755 root root -
d /work/cache 0755 root root -
d /work/env 0755 root root -
d /work/root 0700 root root -
EOF

  cat > "${ROOTFS_DIR}/etc/default/grub" <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=2
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
GRUB_DISTRIBUTOR=Auzix
GRUB_CMDLINE_LINUX_DEFAULT="console=tty1"
GRUB_CMDLINE_LINUX="console=ttyS0,115200n8"
EOF

  cat > "${ROOTFS_DIR}/etc/systemd/system/auzix-layout.service" <<'EOF'
[Unit]
Description=Auzix runtime layout preparation
After=local-fs.target systemd-tmpfiles-setup.service
Before=getty.target multi-user.target graphical.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'mkdir -p /ram/tmp /ram/env /work/home /work/state /work/log /work/cache /work/env /work/root'
ExecStart=/bin/sh -c 'chmod 1777 /ram/tmp'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
WantedBy=graphical.target
EOF

  chroot "${ROOTFS_DIR}" systemctl enable auzix-layout.service
  chroot "${ROOTFS_DIR}" systemctl set-default "${BOOT_TARGET}"
  chroot "${ROOTFS_DIR}" bash -lc "echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen && locale-gen && update-locale LANG=en_US.UTF-8"
}

install_bootloader() {
  log "Installing GRUB and generating initramfs"
  chroot "${ROOTFS_DIR}" update-initramfs -c -k all
  chroot "${ROOTFS_DIR}" grub-install --target=i386-pc --boot-directory=/boot "${LOOPDEV}"
  chroot "${ROOTFS_DIR}" update-grub
}

verify_boot_artifacts() {
  local kernel_image
  local initrd_image

  log "Verifying boot artifacts"
  require_file "${ROOTFS_DIR}/etc/default/grub" "Missing ${ROOTFS_DIR}/etc/default/grub after configuration."
  require_file "${ROOTFS_DIR}/boot/grub/grub.cfg" "Missing GRUB config in ${ROOTFS_DIR}/boot/grub/grub.cfg."

  kernel_image="$(find "${ROOTFS_DIR}/boot" -maxdepth 1 -type f -name 'vmlinuz-*' | head -n 1)"
  initrd_image="$(find "${ROOTFS_DIR}/boot" -maxdepth 1 -type f -name 'initrd.img-*' | head -n 1)"

  if [[ -z "${kernel_image}" ]]; then
    printf 'No kernel image was installed under %s/boot.\n' "${ROOTFS_DIR}" >&2
    exit 1
  fi

  if [[ -z "${initrd_image}" ]]; then
    printf 'No initrd image was installed under %s/boot.\n' "${ROOTFS_DIR}" >&2
    exit 1
  fi
}

finalize_image() {
  rm -f "${ROOTFS_DIR}/usr/sbin/policy-rc.d"
  chroot "${ROOTFS_DIR}" apt-get clean
  qemu-img convert -f raw -O qcow2 "${RAW_IMAGE_PATH}" "${QCOW2_IMAGE_PATH}"
  log "Artifacts written:"
  log "  ${RAW_IMAGE_PATH}"
  log "  ${QCOW2_IMAGE_PATH}"
}

main() {
  require_root "$@"
  trap cleanup EXIT
  require_commands
  resolve_package_profile
  prepare_dirs
  create_image
  mount_image
  bootstrap_base_system
  install_packages
  configure_system
  install_bootloader
  verify_boot_artifacts
  finalize_image
}

main "$@"
