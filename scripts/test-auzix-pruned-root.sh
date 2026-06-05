#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
PRUNED_ROOT="${2:-${ROOT_DIR}/out/auzix-strict/AuzixRoot-pruned}"
IMAGE_NAME="${AUZIX_PRUNED_IMAGE:-auzix-strict:pruned}"
BUSYBOX="/Programs/BusyBox/1.36.1/Commands/busybox"
PROBE="/Programs/AuzixProbe/0.1/Commands/auzix-probe"

if [[ ! -x "${SOURCE_ROOT}${BUSYBOX}" ]]; then
  printf 'BusyBox payload is missing from %s\n' "${SOURCE_ROOT}" >&2
  exit 1
fi

rm -rf "${PRUNED_ROOT}"
mkdir -p "$(dirname "${PRUNED_ROOT}")"
cp -a "${SOURCE_ROOT}" "${PRUNED_ROOT}"

for legacy in bin sbin lib lib64 usr etc var tmp opt home; do
  if [[ -L "${PRUNED_ROOT}/${legacy}" ]]; then
    rm -f "${PRUNED_ROOT}/${legacy}"
  fi
done

tar -C "${PRUNED_ROOT}" -cf - . | docker import \
  --change 'WORKDIR /Work' \
  --change 'ENV PATH=/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands' \
  --change 'CMD ["/Programs/BusyBox/1.36.1/Commands/busybox", "sh"]' \
  - "${IMAGE_NAME}" >/dev/null

docker run --rm "${IMAGE_NAME}" "${BUSYBOX}" sh -c '
set -e
/Programs/AuzixProbe/0.1/Commands/auzix-probe >/System/Logs/auzix-probe/pruned-container-check.log
/Programs/BusyBox/1.36.1/Commands/busybox ls -1 / >/System/Logs/busybox/pruned-root-ls.log
test ! -e /bin
test ! -e /usr
test ! -e /lib
test ! -e /lib64
echo pruned-root-ok
'

printf 'Built and tested %s from %s\n' "${IMAGE_NAME}" "${PRUNED_ROOT}"
