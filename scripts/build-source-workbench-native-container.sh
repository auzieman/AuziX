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
mkdir -p "${ROOTFS_DIR}/System/Build/Commands" "${ROOTFS_DIR}/System/Build/Manifests"
cp "${ROOT_DIR}/packages/base-ports.manifest.json" "${ROOTFS_DIR}/System/Build/Manifests/base-ports.manifest.json"
cp "${ROOT_DIR}/packages/extended-ports.manifest.json" "${ROOTFS_DIR}/System/Build/Manifests/extended-ports.manifest.json"

cat > "${ROOTFS_DIR}/System/Build/Commands/auzix-base-ports-worker" <<'WORKER'
#!/bin/sh
set -eu

MANIFEST="${AUZIX_BASE_PORTS_MANIFEST:-/System/Build/Manifests/base-ports.manifest.json}"
OUT_DIR="${AUZIX_BASE_PORTS_OUT:-/Work/base-ports-worker}"
MODE="${AUZIX_BASE_PORTS_MODE:-plan-only}"
SLEEP_SECONDS="${AUZIX_BASE_PORTS_SLEEP_SECONDS:-3600}"
OLLAMA_URL="${AUZIX_OLLAMA_URL:-}"
OLLAMA_MODEL="${AUZIX_OLLAMA_MODEL:-}"

mkdir -p "${OUT_DIR}"

write_plan() {
  jq -r '
    "AuZiX base ports worker\nmanifest=" + "'"${MANIFEST}"'" + "\nprofile=" + .profile + "\n",
    (.phases[] |
      "## " + .id + "\n" + .purpose + "\n" +
      ((.targets // []) | map("  - " + .name + " source=" + .source.package + " prefix=" + .prefix + " promotes=" + ((.promotes // []) | join(","))) | join("\n")) +
      "\n")
  ' "${MANIFEST}" > "${OUT_DIR}/base-ports-plan.txt"

  jq -n \
    --arg format "auzix-base-ports-worker-v1" \
    --arg status "planned" \
    --arg mode "${MODE}" \
    --arg manifest "${MANIFEST}" \
    --arg out_dir "${OUT_DIR}" \
    --arg ollama_url "${OLLAMA_URL}" \
    --arg ollama_model "${OLLAMA_MODEL}" \
    --argjson phases "$(jq '.phases | length' "${MANIFEST}")" \
    --argjson targets "$(jq '[.phases[].targets[]] | length' "${MANIFEST}")" \
    '{
      format: $format,
      status: $status,
      mode: $mode,
      manifest: $manifest,
      out_dir: $out_dir,
      phase_count: $phases,
      target_count: $targets,
      ollama: {
        url: $ollama_url,
        model: $ollama_model,
        trigger: "failed-target-only",
        authority: "advisory-contract-patch-only"
      },
      note: "Plan-only background worker. Build execution remains disabled until phase runners are explicit."
    }' > "${OUT_DIR}/base-ports-worker-report.json"
}

write_plan

if [ "${MODE}" = "once" ] || [ "${MODE}" = "plan-only-once" ]; then
  exit 0
fi

echo "auzix-base-ports-worker ready mode=${MODE} out=${OUT_DIR}"
while :; do
  sleep "${SLEEP_SECONDS}"
  write_plan
done
WORKER
chmod 0755 "${ROOTFS_DIR}/System/Build/Commands/auzix-base-ports-worker"

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
  --arg base_ports_manifest "/System/Build/Manifests/base-ports.manifest.json" \
  --arg base_ports_worker "/System/Build/Commands/auzix-base-ports-worker" \
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
    base_ports: {
      manifest: $base_ports_manifest,
      worker: $base_ports_worker,
      default_mode: "plan-only"
    },
    source_validation: $validation,
    notes: "Phase 3 native-layout container. Debian currently supplies temporary bash/jq/lua review tools until those are package-owned under /Programs."
  }' > "${REPORT_PATH}"

log "report: ${REPORT_PATH}"
log "image: ${IMAGE}"
log "complete"
