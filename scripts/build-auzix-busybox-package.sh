#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
BUSYBOX_VERSION="${AUZIX_BUSYBOX_VERSION:-1.36.1}"
TARBALL="busybox-${BUSYBOX_VERSION}.tar.bz2"
SOURCE_URL="${AUZIX_BUSYBOX_URL:-https://busybox.net/downloads/${TARBALL}}"
SOURCE_CACHE="${ROOT_DIR}/downloads/${TARBALL}"
BUILD_ROOT="${AUZIX_BUSYBOX_BUILD_ROOT:-${TMPDIR:-/tmp}/auzix-strict-build}"
SOURCE_DIR="${BUILD_ROOT}/busybox-${BUSYBOX_VERSION}"
PROGRAM_ROOT="${AUZIX_ROOT}/Programs/BusyBox/${BUSYBOX_VERSION}"
COMMAND_PATH="${PROGRAM_ROOT}/Commands/busybox"
RECEIPT_PATH="${AUZIX_ROOT}/System/PackageDB/BusyBox-${BUSYBOX_VERSION}.auzix.json"

log() {
  printf '[auzix-busybox] %s\n' "$*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

write_receipt() {
  cat > "${RECEIPT_PATH}" <<JSON
{
  "name": "BusyBox",
  "version": "${BUSYBOX_VERSION}",
  "kind": "program",
  "migration_stage": "stage-2-native-paths",
  "prefix": "/Programs/BusyBox/${BUSYBOX_VERSION}",
  "paths": {
    "current": "/Programs/BusyBox/current",
    "libraries": "/Programs/BusyBox/${BUSYBOX_VERSION}/Libraries"
  },
  "commands": [
    "/Programs/BusyBox/${BUSYBOX_VERSION}/Commands/busybox"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/busybox",
    "/System/Compatibility/bin/sh",
    "/System/Compatibility/bin/fdisk",
    "/System/Compatibility/bin/id",
    "/System/Compatibility/bin/ip",
    "/System/Compatibility/bin/ping",
    "/System/Compatibility/bin/udhcpc",
    "/System/Compatibility/bin/wget",
    "/System/Compatibility/bin/mkfs.ext2",
    "/System/Compatibility/bin/ls",
    "/System/Compatibility/bin/mount",
    "/System/Compatibility/bin/readlink",
    "/System/Compatibility/bin/sed",
    "/System/Compatibility/bin/which"
  ]
}
JSON
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing. Run scaffold-auzix-strict-root.sh first: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

if [[ -x "${COMMAND_PATH}" && -L "${AUZIX_ROOT}/System/Compatibility/bin/sh" ]]; then
  log "Reusing existing BusyBox payload at ${COMMAND_PATH}"
  mkdir -p "${AUZIX_ROOT}/System/Compatibility/bin"
  ln -sfn /Programs/BusyBox/"${BUSYBOX_VERSION}" \
    "${AUZIX_ROOT}/Programs/BusyBox/current"
  ln -sfn /Programs/BusyBox/"${BUSYBOX_VERSION}"/Commands/busybox \
    "${AUZIX_ROOT}/System/Compatibility/bin/busybox"
  for applet in \
    sh \
    ash \
    awk \
    basename \
    blkid \
    cat \
    chmod \
    chown \
    cp \
    cut \
    date \
    dd \
    dirname \
    dmesg \
    echo \
    env \
    fdisk \
    find \
    grep \
    head \
    hostname \
    id \
    ifconfig \
    ip \
    ls \
    mdev \
    mkdir \
    mkfs.ext2 \
    mkfs.vfat \
    mknod \
    mount \
    mv \
    nc \
    nslookup \
    partprobe \
    ping \
    pivot_root \
    poweroff \
    ps \
    pwd \
    readlink \
    reboot \
    route \
    rm \
    sed \
    sleep \
    sort \
    switch_root \
    tail \
    tar \
    test \
    tr \
    udhcpc \
    umount \
    uname \
    vi \
    wc \
    wget \
    which \
    xargs
  do
    ln -sfn /Programs/BusyBox/"${BUSYBOX_VERSION}"/Commands/busybox \
      "${AUZIX_ROOT}/System/Compatibility/bin/${applet}"
  done
  write_receipt
  "${COMMAND_PATH}" sh -c 'echo busybox-shell-ok' > "${AUZIX_ROOT}/System/Logs/busybox/install-check.log"
  file "${COMMAND_PATH}"
  if command -v ldd >/dev/null 2>&1; then
    ldd "${COMMAND_PATH}" || true
  fi
  exit 0
fi

for cmd in make gcc tar sed install; do
  require_cmd "${cmd}"
done

if [[ ! -f "${SOURCE_CACHE}" ]]; then
  require_cmd wget
  mkdir -p "$(dirname "${SOURCE_CACHE}")"
  log "Fetching ${SOURCE_URL}"
  DOWNLOAD_TMP="${TMPDIR:-/tmp}/${TARBALL}.$$"
  wget -O "${DOWNLOAD_TMP}" "${SOURCE_URL}"
  install -m 0644 "${DOWNLOAD_TMP}" "${SOURCE_CACHE}"
  rm -f "${DOWNLOAD_TMP}"
fi

rm -rf "${SOURCE_DIR}"
mkdir -p "${BUILD_ROOT}"
tar -xf "${SOURCE_CACHE}" -C "${BUILD_ROOT}"

log "Configuring BusyBox ${BUSYBOX_VERSION} for a static shell payload"
env -u ARCH -u CROSS_COMPILE make -C "${SOURCE_DIR}" defconfig >/dev/null
sed -i \
  -e 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' \
  -e 's/^CONFIG_INSTALL_APPLET_SYMLINKS=y/CONFIG_INSTALL_APPLET_SYMLINKS=y/' \
  "${SOURCE_DIR}/.config"
set +o pipefail
yes "" | env -u ARCH -u CROSS_COMPILE make -C "${SOURCE_DIR}" oldconfig >/dev/null
set -o pipefail

log "Building BusyBox"
env -u ARCH -u CROSS_COMPILE make -C "${SOURCE_DIR}" -j"$(nproc)" busybox

mkdir -p \
  "${PROGRAM_ROOT}/Commands" \
  "${PROGRAM_ROOT}/Libraries" \
  "${PROGRAM_ROOT}/Resources" \
  "${AUZIX_ROOT}/System/Settings/busybox" \
  "${AUZIX_ROOT}/System/State/busybox" \
  "${AUZIX_ROOT}/System/Logs/busybox" \
  "${AUZIX_ROOT}/System/Compatibility/bin"

install -m 0755 "${SOURCE_DIR}/busybox" "${COMMAND_PATH}"
ln -sfn /Programs/BusyBox/"${BUSYBOX_VERSION}" \
  "${AUZIX_ROOT}/Programs/BusyBox/current"
ln -sfn /Programs/BusyBox/"${BUSYBOX_VERSION}"/Commands/busybox \
  "${AUZIX_ROOT}/System/Compatibility/bin/busybox"
for applet in \
  sh \
  ash \
  awk \
  basename \
  blkid \
  cat \
  chmod \
  chown \
  cp \
  cut \
  date \
  dd \
  dirname \
  dmesg \
  echo \
  env \
  fdisk \
  find \
  grep \
  head \
  hostname \
  id \
  ifconfig \
  ip \
  ls \
  mdev \
  mkdir \
  mkfs.ext2 \
  mkfs.vfat \
  mknod \
  mount \
  mv \
  nc \
  nslookup \
  partprobe \
  ping \
  pivot_root \
  poweroff \
  ps \
  pwd \
  readlink \
  reboot \
  route \
  rm \
  sed \
  sleep \
  sort \
  switch_root \
  tail \
  tar \
  test \
  tr \
  udhcpc \
  umount \
  uname \
  vi \
  wc \
  wget \
  which \
  xargs
do
  ln -sfn /Programs/BusyBox/"${BUSYBOX_VERSION}"/Commands/busybox \
    "${AUZIX_ROOT}/System/Compatibility/bin/${applet}"
done

write_receipt

"${COMMAND_PATH}" sh -c 'echo busybox-shell-ok' > "${AUZIX_ROOT}/System/Logs/busybox/install-check.log"
file "${COMMAND_PATH}"
if command -v ldd >/dev/null 2>&1; then
  ldd "${COMMAND_PATH}" || true
fi

log "BusyBox installed"
