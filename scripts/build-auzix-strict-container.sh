#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${AUZIX_STRICT_IMAGE:-auzix-strict:local}"
AUZIX_ROOT="${ROOT_DIR}/out/auzix-strict/AuzixRoot"
BUSYBOX="${AUZIX_ROOT}/Programs/BusyBox/current/Commands/busybox"

if [[ ! -x "${BUSYBOX}" ]]; then
  printf 'BusyBox payload is missing. Run make auzix-strict-busybox first.\n' >&2
  exit 1
fi

stage="$(mktemp -d "${TMPDIR:-/tmp}/auzix-strict-container.XXXXXX")"
cleanup() {
  rm -rf "${stage}"
}
trap cleanup EXIT

# Docker injects runtime files under /etc.  A VM/live AUZiX root may use
# /etc -> /System/Settings, but OCI imports need a real /etc directory with
# only the specific classic surfaces that compiled third-party defaults still
# probe.  Keep this narrow: trust store only, not a broad legacy root rollback.
mkdir -p "${stage}/etc"
ln -s /System/Compatibility/etc/ssl "${stage}/etc/ssl"

tar -C "${AUZIX_ROOT}" --exclude='./etc' -cf "${stage}/root.tar" .
tar -C "${stage}" -rf "${stage}/root.tar" etc

docker import \
  --change 'WORKDIR /Work' \
  --change 'ENV PATH=/System/Compatibility/bin:/System/Compatibility/sbin:/Programs/BusyBox/current/Commands:/Programs/Flatpak/current/Commands:/Programs/Glances/current/Commands:/Programs/Htop/current/Commands:/Programs/Nano/current/Commands' \
  --change 'ENV SSL_CERT_DIR=/System/Compatibility/etc/ssl/certs' \
  --change 'ENV SSL_CERT_FILE=/System/Compatibility/etc/ssl/certs/ca-certificates.crt' \
  --change 'ENV CURL_CA_BUNDLE=/System/Compatibility/etc/ssl/certs/ca-certificates.crt' \
  --change 'ENV REQUESTS_CA_BUNDLE=/System/Compatibility/etc/ssl/certs/ca-certificates.crt' \
  --change 'CMD ["/Programs/BusyBox/current/Commands/busybox", "sh"]' \
  - "${IMAGE_NAME}" <"${stage}/root.tar"
printf 'Built %s\n' "${IMAGE_NAME}"
printf 'Run shell: docker run --rm -it %s\n' "${IMAGE_NAME}"
