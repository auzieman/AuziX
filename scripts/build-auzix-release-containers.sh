#!/usr/bin/env bash
set -euo pipefail

# This script is intended for lab-build/R730.  Refuse the developer laptop so
# multi-gigabyte roots and Docker cache cannot consume workstation storage.
if [[ "$(hostname -s)" != "lab-ai-worker" && "$(hostname -s)" != "r730-ai-01" ]]; then
  printf 'Refusing release-container assembly on %s; run on lab-build/R730.\n' "$(hostname -s)" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_ID="${AUZIX_RELEASE_ID:-trixie-consolidated-20260826-r3}"
RELEASE_ROOT="${AUZIX_RELEASE_ROOT:-/var/lib/auzix-build/releases/${RELEASE_ID}}"
PREPARED_ROOT="${AUZIX_PREPARED_ROOT:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
RUN_ID="${AUZIX_CONTAINER_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
WORK="${AUZIX_CONTAINER_WORK:-/var/lib/auzix-build/container-runs/${RUN_ID}}"
BUSYBOX_IMAGE="${AUZIX_BUSYBOX_IMAGE:-auzix/service:zero-busybox-${RELEASE_ID}}"
NGINX_IMAGE="${AUZIX_NGINX_IMAGE:-auzix/service:one-nginx-${RELEASE_ID}}"
MONSTER_IMAGE="${AUZIX_MONSTER_IMAGE:-auzix/validation:pre-hdd-${RELEASE_ID}}"
INDEX="${RELEASE_ROOT}/repo/index.json"

log() { printf '[auzix-three-containers] %s\n' "$*"; }
fail() { log "FAIL: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }
copy_tree() {
  local source="$1" target="$2"
  mkdir -p "${target}"
  tar --numeric-owner -C "${source}" -cf - . | tar --numeric-owner -C "${target}" -xf -
}

need docker; need jq; need python3; need tar; need sha256sum
[[ -s "${INDEX}" ]] || fail "missing frozen repository index: ${INDEX}"
[[ -d "${PREPARED_ROOT}/System" && -d "${PREPARED_ROOT}/Programs/Busybox" ]] \
  || fail "prepared AUZiX root is incomplete: ${PREPARED_ROOT}"
[[ ! -e "${WORK}" ]] || fail "run workspace already exists: ${WORK}"

mkdir -p "${WORK}"/{zero-busybox,one-nginx,pre-hdd}/root "${WORK}/receipts"
cp "${ROOT_DIR}/docker/release/zero-busybox/Dockerfile" "${WORK}/zero-busybox/Dockerfile"
cp "${ROOT_DIR}/docker/release/one-nginx/Dockerfile" "${WORK}/one-nginx/Dockerfile"
cp "${ROOT_DIR}/docker/release/pre-hdd/Dockerfile" "${WORK}/pre-hdd/Dockerfile"

# Image zero: the canonical AUZiX substrate plus the newly packaged BusyBox.
for path in System Programs/BusyBox Programs/Busybox; do
  copy_tree "${PREPARED_ROOT}/${path}" "${WORK}/zero-busybox/root/${path}"
done
mkdir -p "${WORK}/zero-busybox/root"/{Services,Work,Users/root}

# Image one: resolve nginx once from the frozen index and add that ordered
# package closure over image zero.  There is no package discovery or rebuild.
python3 - "${INDEX}" "${WORK}/nginx-order.txt" <<'PY'
import json, sys
index, output = sys.argv[1:]
packages = json.load(open(index)).get("packages", [])
by_name = {p["name"].casefold(): p for p in packages}
seen, active, ordered = set(), set(), []
def visit(name):
    key = name.casefold()
    if key in seen: return
    if key in active: raise SystemExit(f"dependency cycle at {name}")
    package = by_name.get(key)
    if package is None: raise SystemExit(f"missing frozen dependency {name}")
    active.add(key)
    for dependency in package.get("depends") or []: visit(dependency)
    active.remove(key); seen.add(key); ordered.append(package["package"])
visit("Nginx")
open(output, "w").write("".join(p + "\n" for p in ordered))
PY
while IFS= read -r archive; do
  [[ -n "${archive}" ]] || continue
  tar --numeric-owner -xzf "${RELEASE_ROOT}/repo/packages/${archive}" -C "${WORK}/one-nginx/root"
done <"${WORK}/nginx-order.txt"

# Image monster: exact prepared package-built root used by the HDD lane.
copy_tree "${PREPARED_ROOT}" "${WORK}/pre-hdd/root"

docker build --pull=false -t "${BUSYBOX_IMAGE}" "${WORK}/zero-busybox"
docker run --rm "${BUSYBOX_IMAGE}" /Programs/Busybox/current/Commands/busybox sh -ec \
  'test -x /System/Libraries/Runtime/glibc/libc.so.6; test ! -e /usr; echo auzix-zero-ok'

docker build --pull=false --build-arg "BASE_IMAGE=${BUSYBOX_IMAGE}" -t "${NGINX_IMAGE}" "${WORK}/one-nginx"
docker run --rm --user 0:0 "${NGINX_IMAGE}" /Programs/Nginx/current/Commands/nginx -t \
  -c /System/Settings/Nginx/nginx.conf -p /

docker build --pull=false -t "${MONSTER_IMAGE}" "${WORK}/pre-hdd"
docker run --rm "${MONSTER_IMAGE}" /Programs/Busybox/current/Commands/busybox sh -ec \
  'test -s /System/State/packages/installed.json; test -x /System/Libraries/Runtime/glibc/libc.so.6; echo auzix-pre-hdd-ok'

for tuple in "busybox:${BUSYBOX_IMAGE}" "nginx:${NGINX_IMAGE}" "pre-hdd:${MONSTER_IMAGE}"; do
  name="${tuple%%:*}"; image="${tuple#*:}"
  docker image inspect --format '{{.Id}} {{.Size}}' "${image}" | \
    awk -v name="${name}" -v image="${image}" -v release="${RELEASE_ID}" \
      '{printf "format=auzix-container-receipt-v1\nname=%s\nimage=%s\nimage_id=%s\nsize=%s\nrelease_id=%s\nstatus=pass\n",name,image,$1,$2,release}' \
      >"${WORK}/receipts/${name}.receipt"
done

log "PASS run=${RUN_ID} work=${WORK}"
log "images=${BUSYBOX_IMAGE} ${NGINX_IMAGE} ${MONSTER_IMAGE}"
