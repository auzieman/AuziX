#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${AUZIX_STRICT_IMAGE:-auzix-strict:local}"
AUZIX_ROOT="${ROOT_DIR}/out/auzix-strict/AuzixRoot"
BUSYBOX="${AUZIX_ROOT}/Programs/BusyBox/1.36.1/Commands/busybox"

if [[ ! -x "${BUSYBOX}" ]]; then
  printf 'BusyBox payload is missing. Run make auzix-strict-busybox first.\n' >&2
  exit 1
fi

tar -C "${AUZIX_ROOT}" -cf - . | docker import \
  --change 'WORKDIR /Work' \
  --change 'ENV PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands' \
  --change 'CMD ["/Programs/BusyBox/1.36.1/Commands/busybox", "sh"]' \
  - "${IMAGE_NAME}"
printf 'Built %s\n' "${IMAGE_NAME}"
printf 'Run shell: docker run --rm -it %s\n' "${IMAGE_NAME}"
