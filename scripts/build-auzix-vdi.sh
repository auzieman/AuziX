#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${ROOT_DIR}/artifacts/auzix"
IMAGE_NAME="${AUZIX_IMAGE_NAME:-auzix}"
RAW_IMAGE_PATH="${ARTIFACT_DIR}/${IMAGE_NAME}.raw"
QCOW2_IMAGE_PATH="${ARTIFACT_DIR}/${IMAGE_NAME}.qcow2"
VDI_IMAGE_PATH="${ARTIFACT_DIR}/${IMAGE_NAME}.vdi"
SOURCE_IMAGE="${1:-}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/build-auzix-vdi.sh [source-image]

Default source resolution order:
  1. explicit positional argument
  2. artifacts/auzix/${AUZIX_IMAGE_NAME}.raw
  3. artifacts/auzix/${AUZIX_IMAGE_NAME}.qcow2
EOF
}

resolve_source_image() {
  if [[ $# -gt 0 && -n "${1}" ]]; then
    printf '%s\n' "${1}"
    return 0
  fi

  local candidate
  for candidate in "${RAW_IMAGE_PATH}" "${QCOW2_IMAGE_PATH}"; do
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

if ! command -v qemu-img >/dev/null 2>&1; then
  echo "qemu-img is required but not installed." >&2
  exit 1
fi

SOURCE_IMAGE="$(resolve_source_image "${SOURCE_IMAGE}")" || {
  echo "No Auzix source image found for VDI conversion." >&2
  exit 1
}

if [[ ! -f "${SOURCE_IMAGE}" ]]; then
  echo "Source image not found: ${SOURCE_IMAGE}" >&2
  exit 1
fi

mkdir -p "${ARTIFACT_DIR}"
rm -f "${VDI_IMAGE_PATH}"

case "${SOURCE_IMAGE}" in
  *.qcow2)
    INPUT_FORMAT="qcow2"
    ;;
  *)
    INPUT_FORMAT="raw"
    ;;
esac

echo "Converting ${SOURCE_IMAGE} -> ${VDI_IMAGE_PATH}"
qemu-img convert -p -f "${INPUT_FORMAT}" -O vdi "${SOURCE_IMAGE}" "${VDI_IMAGE_PATH}"
echo "VDI created at ${VDI_IMAGE_PATH}"
