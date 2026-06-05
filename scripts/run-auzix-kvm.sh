#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${ROOT_DIR}/artifacts/auzix"
DEFAULT_DISK_BASENAME="${AUZIX_DISK_NAME:-auzix}"
DEFAULT_MEMORY_MB="${AUZIX_MEMORY_MB:-2048}"
DEFAULT_CPUS="${AUZIX_CPUS:-2}"
DEFAULT_SSH_PORT="${AUZIX_SSH_PORT:-2222}"
DEFAULT_USERNAME="${AUZIX_USERNAME:-auzi}"
DEFAULT_USER_PASSWORD="${AUZIX_PASSWORD:-auzi}"
DEFAULT_ROOT_PASSWORD="${AUZIX_ROOT_PASSWORD:-root}"
ACCEL_MODE="kvm"
CPU_MODEL="host"
DRIVE_FORMAT="raw"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run-auzix-kvm.sh [disk-image]

Environment overrides:
  AUZIX_DISK_NAME    Base disk name under artifacts/auzix/ (default: auzix)
  AUZIX_MEMORY_MB    Guest RAM in MiB (default: 2048)
  AUZIX_CPUS         Guest vCPU count (default: 2)
  AUZIX_SSH_PORT     Host TCP port forwarded to guest 22 (default: 2222)
  AUZIX_HEADLESS     Set to 0 to enable a graphical QEMU window
  AUZIX_QEMU_APPEND  Extra arguments appended verbatim to qemu-system-x86_64

Disk image resolution order:
  1. explicit positional argument
  2. artifacts/auzix/${AUZIX_DISK_NAME}.qcow2
  3. artifacts/auzix/${AUZIX_DISK_NAME}.img
  4. artifacts/auzix/${AUZIX_DISK_NAME}.raw

Examples:
  ./scripts/run-auzix-kvm.sh
  ./scripts/run-auzix-kvm.sh artifacts/auzix/auzix-shell.img
  AUZIX_HEADLESS=0 AUZIX_MEMORY_MB=4096 ./scripts/run-auzix-kvm.sh
EOF
}

resolve_disk_image() {
  if [[ $# -gt 0 && -n "${1}" ]]; then
    printf '%s\n' "$1"
    return 0
  fi

  local candidate
  for candidate in \
    "${ARTIFACT_DIR}/${DEFAULT_DISK_BASENAME}.qcow2" \
    "${ARTIFACT_DIR}/${DEFAULT_DISK_BASENAME}.img" \
    "${ARTIFACT_DIR}/${DEFAULT_DISK_BASENAME}.raw"
  do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "qemu-system-x86_64 is required but not installed." >&2
  exit 1
fi

DISK_IMAGE="$(resolve_disk_image "${1:-}")" || {
  echo "No Auzix disk image found." >&2
  echo "Expected one of:" >&2
  echo "  ${ARTIFACT_DIR}/${DEFAULT_DISK_BASENAME}.qcow2" >&2
  echo "  ${ARTIFACT_DIR}/${DEFAULT_DISK_BASENAME}.img" >&2
  echo "  ${ARTIFACT_DIR}/${DEFAULT_DISK_BASENAME}.raw" >&2
  echo "Or pass an explicit image path." >&2
  exit 1
}

if [[ ! -f "${DISK_IMAGE}" ]]; then
  echo "Disk image not found: ${DISK_IMAGE}" >&2
  exit 1
fi

HEADLESS="${AUZIX_HEADLESS:-1}"

if [[ ! -e /dev/kvm ]]; then
  echo "Warning: /dev/kvm is not available here. QEMU will fall back to TCG." >&2
  ACCEL_MODE="tcg"
  CPU_MODEL="max"
fi

case "${DISK_IMAGE}" in
  *.qcow2)
    DRIVE_FORMAT="qcow2"
    ;;
esac

QEMU_ARGS=(
  -name "auzix-dev"
  -machine "q35,accel=${ACCEL_MODE}"
  -cpu "${CPU_MODEL}"
  -smp "${DEFAULT_CPUS}"
  -m "${DEFAULT_MEMORY_MB}"
  -drive "file=${DISK_IMAGE},if=virtio,format=${DRIVE_FORMAT}"
  -netdev "user,id=net0,hostfwd=tcp::${DEFAULT_SSH_PORT}-:22"
  -device virtio-net-pci,netdev=net0
  -device virtio-rng-pci
  -serial mon:stdio
  -no-reboot
)

if [[ "${HEADLESS}" == "1" ]]; then
  QEMU_ARGS+=(-nographic)
else
  QEMU_ARGS+=(-display default)
fi

if [[ -n "${AUZIX_QEMU_APPEND:-}" ]]; then
  # Deliberately split on shell words so users can append ordinary QEMU flags.
  # shellcheck disable=SC2206
  EXTRA_ARGS=( ${AUZIX_QEMU_APPEND} )
  QEMU_ARGS+=("${EXTRA_ARGS[@]}")
fi

echo "Launching Auzix image: ${DISK_IMAGE}"
echo "Memory: ${DEFAULT_MEMORY_MB} MiB, vCPUs: ${DEFAULT_CPUS}, SSH forward: localhost:${DEFAULT_SSH_PORT} -> guest:22"
echo "Login hints: user=${DEFAULT_USERNAME} password=${DEFAULT_USER_PASSWORD} | root password=${DEFAULT_ROOT_PASSWORD}"

exec qemu-system-x86_64 "${QEMU_ARGS[@]}"
