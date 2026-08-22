#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STRICT_ROOT="${AUZIX_STRICT_ROOT:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
IMAGE_NAME="${AUZIX_BUSYBOX_IMAGE:-auzix/service:zero-busybox}"
BUSYBOX=/Programs/BusyBox/current/Commands/busybox
HOST_BUSYBOX="${STRICT_ROOT}/Programs/BusyBox/1.36.1/Commands/busybox"

if [[ ! -x "${HOST_BUSYBOX}" ]]; then
  printf 'BusyBox current payload is missing. Run make auzix-strict-busybox first.\n' >&2
  exit 1
fi

stage="$(mktemp -d "${TMPDIR:-/tmp}/auzix-busybox-zero.XXXXXX")"
cleanup() {
  rm -rf "${stage}"
}
trap cleanup EXIT

mkdir -p \
  "${stage}/Programs" \
  "${stage}/Services" \
  "${stage}/System/Compatibility/bin" \
  "${stage}/System/Logs" \
  "${stage}/System/Settings" \
  "${stage}/System/State" \
  "${stage}/Work"

cp -a "${STRICT_ROOT}/Programs/BusyBox" "${stage}/Programs/"
cp -a "${STRICT_ROOT}/System/Compatibility/bin/." \
  "${stage}/System/Compatibility/bin/"

tar -C "${stage}" -cf - . | docker import \
  --change 'WORKDIR /Work' \
  --change 'ENV PATH=/System/Compatibility/bin:/Programs/BusyBox/current/Commands' \
  --change 'CMD ["/Programs/BusyBox/current/Commands/busybox", "sh"]' \
  - "${IMAGE_NAME}" >/dev/null

docker run --rm "${IMAGE_NAME}" "${BUSYBOX}" sh -ec '
  test ! -e /bin
  test ! -e /usr
  test ! -e /lib
  test ! -e /lib64
  test -x /Programs/BusyBox/current/Commands/busybox
  echo auzix-container-zero-ok
'

docker image inspect --format '{{index .RepoTags 0}} {{.Size}} bytes' "${IMAGE_NAME}"
