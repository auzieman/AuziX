#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${ROOT_DIR}/artifacts/auzix"
IMAGE_NAME="${AUZIX_IMAGE_NAME:-auzix}"
VM_NAME="${AUZIX_VBOX_VM_NAME:-Auzix}"
VDI_IMAGE_PATH="${ARTIFACT_DIR}/${IMAGE_NAME}.vdi"
MEMORY_MB="${AUZIX_MEMORY_MB:-2048}"
CPUS="${AUZIX_CPUS:-2}"
VM_DIR="${HOME}/VirtualBox VMs/${VM_NAME}"
SERIAL_LOG_PATH="${AUZIX_VBOX_SERIAL_LOG_PATH:-${VM_DIR}/serial.log}"
HEADLESS="${AUZIX_HEADLESS:-1}"

if ! command -v VBoxManage >/dev/null 2>&1; then
  echo "VBoxManage is required but not installed." >&2
  exit 1
fi

if [[ ! -f "${VDI_IMAGE_PATH}" ]]; then
  echo "VDI image not found: ${VDI_IMAGE_PATH}" >&2
  echo "Run ./scripts/build-auzix-vdi.sh first." >&2
  exit 1
fi

if VBoxManage showvminfo "${VM_NAME}" >/dev/null 2>&1; then
  echo "VirtualBox VM already exists: ${VM_NAME}" >&2
  exit 1
fi

echo "Creating VirtualBox VM ${VM_NAME}"
VBoxManage createvm --name "${VM_NAME}" --ostype Debian_64 --register
VBoxManage modifyvm "${VM_NAME}" \
  --memory "${MEMORY_MB}" \
  --cpus "${CPUS}" \
  --chipset piix3 \
  --graphicscontroller vmsvga \
  --bootmenu messageandmenu \
  --audio-enabled off \
  --clipboard-mode disabled \
  --draganddrop disabled \
  --uart1 0x3F8 4 \
  --uartmode1 file "${SERIAL_LOG_PATH}" \
  --boot1 disk \
  --nic1 nat
VBoxManage storagectl "${VM_NAME}" --name "SATA Controller" --add sata --controller IntelAhci
VBoxManage storageattach "${VM_NAME}" \
  --storagectl "SATA Controller" \
  --port 0 \
  --device 0 \
  --type hdd \
  --medium "${VDI_IMAGE_PATH}"

echo "VirtualBox VM created: ${VM_NAME}"
echo "Serial boot log: ${SERIAL_LOG_PATH}"

if [[ "${HEADLESS}" == "1" ]]; then
  echo "Starting ${VM_NAME} headless"
  VBoxManage startvm "${VM_NAME}" --type headless
else
  echo "Starting ${VM_NAME} with GUI"
  VBoxManage startvm "${VM_NAME}" --type gui
fi
