#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${AUZIX_WORKBENCH_REPORT_DIR:-${ROOT_DIR}/out/source-workbench}"
TARGET_ROOT="${AUZIX_TARGET_ROOT:-${REPORT_DIR}/AuZiXTarget}"
NATIVE_DIR="${REPORT_DIR}/native-container"
CONTEXT_DIR="${NATIVE_DIR}/context"
ROOTFS_DIR="${CONTEXT_DIR}/rootfs"
IMAGE="${AUZIX_NATIVE_WORKBENCH_IMAGE:-auzix/native-workbench:phase3}"
REPORT_PATH="${NATIVE_DIR}/native-container-report.json"
IMAGE_TAR="${NATIVE_DIR}/native-workbench-image.tar"
ROOTFS_TAR="${NATIVE_DIR}/native-workbench-rootfs.tar"

log() {
  printf '[native-workbench] %s\n' "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

require_cmd docker
require_cmd jq

log "refreshing source workbench target"
"${ROOT_DIR}/scripts/source-workbench-boot.sh"

jq -e '
  .status == "passed" and
  .checks.shared_library_root == "/System/Libraries" and
  .checks.split_library_path_count == 0
' "${REPORT_DIR}/validation-report.json" >/dev/null

rm -rf "${CONTEXT_DIR}"
mkdir -p "${ROOTFS_DIR}" "${NATIVE_DIR}"
cp -a "${TARGET_ROOT}/." "${ROOTFS_DIR}/"

cat > "${CONTEXT_DIR}/Dockerfile" <<'DOCKERFILE'
# syntax=docker/dockerfile:1.6
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      jq \
      lua5.4 \
      procps && \
    rm -rf /var/lib/apt/lists/*

COPY rootfs/ /

RUN mkdir -p \
      /Programs/Lua/current/Commands \
      /System/Tools \
      /System/State \
      /Work && \
    ln -sf /usr/bin/lua5.4 /Programs/Lua/current/Commands/lua && \
    ln -sf /bin/bash /System/Tools/bash && \
    ln -sf /usr/bin/jq /System/Tools/jq

ENV LD_LIBRARY_PATH=/System/Libraries
WORKDIR /Work

CMD ["/bin/bash", "-lc", "/Programs/Lua/current/Commands/lua /System/S/system-startup.lua && echo 'phase3 native workbench ready' && sleep infinity"]
DOCKERFILE

log "building ${IMAGE}"
docker build -t "${IMAGE}" -f "${CONTEXT_DIR}/Dockerfile" "${CONTEXT_DIR}"

log "smoke testing ${IMAGE}"
docker run --rm "${IMAGE}" /bin/bash -lc '
  set -euo pipefail
  test -d /System/Libraries
  test -s /System/Settings/runtime-paths.json
  jq -e ".library_policy.shared_root == \"/System/Libraries\"" /System/Settings/runtime-paths.json >/dev/null
  /Programs/Lua/current/Commands/lua /System/S/system-startup.lua >/tmp/auzix-startup.log
  test -s /System/State/source-workbench-startup.log
'

log "writing image artifact ${IMAGE_TAR}"
docker save -o "${IMAGE_TAR}" "${IMAGE}"

log "writing exported rootfs artifact ${ROOTFS_TAR}"
container_id="$(docker create "${IMAGE}" /bin/true)"
cleanup_container() {
  docker rm -f "${container_id}" >/dev/null 2>&1 || true
}
trap cleanup_container EXIT
docker export -o "${ROOTFS_TAR}" "${container_id}"
cleanup_container
trap - EXIT

jq -n \
  --arg format "auzix-native-workbench-container-v1" \
  --arg status "passed" \
  --arg image "${IMAGE}" \
  --arg context "${CONTEXT_DIR}" \
  --arg rootfs "${ROOTFS_DIR}" \
  --arg image_tar "${IMAGE_TAR}" \
  --arg rootfs_tar "${ROOTFS_TAR}" \
  --arg validation "${REPORT_DIR}/validation-report.json" \
  '{
    format: $format,
    status: $status,
    image: $image,
    context: $context,
    rootfs: $rootfs,
    artifacts: {
      docker_image_tar: $image_tar,
      exported_rootfs_tar: $rootfs_tar
    },
    source_validation: $validation,
    notes: "Phase 3 native-layout container. Debian currently supplies temporary bash/jq/lua review tools until those are package-owned under /Programs."
  }' > "${REPORT_PATH}"

log "report: ${REPORT_PATH}"
log "image: ${IMAGE}"
log "complete"
