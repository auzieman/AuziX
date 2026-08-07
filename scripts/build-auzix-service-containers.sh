#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STRICT_ROOT="${AUZIX_STRICT_ROOT:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
PORT_ROOT="${AUZIX_EXTENDED_ROOT:-${ROOT_DIR}/out/extended-ports/AuZiXRoot}"
BUSYBOX_IMAGE="${AUZIX_BUSYBOX_IMAGE:-auzix/service:zero-busybox}"
NGINX_IMAGE="${AUZIX_NGINX_IMAGE:-auzix/service:one-nginx}"
BUSYBOX=/Programs/BusyBox/1.36.1/Commands/busybox
NGINX_VERSION="$(basename "$(readlink "${PORT_ROOT}/Programs/Nginx/current")")"

test -x "${STRICT_ROOT}${BUSYBOX}"
test -x "${PORT_ROOT}/Programs/Nginx/${NGINX_VERSION}/Commands/nginx"

stage="$(mktemp -d "${TMPDIR:-/tmp}/auzix-service-containers.XXXXXX")"
cleanup() {
  rm -rf "${stage}"
}
trap cleanup EXIT

make_skeleton() {
  local root="$1"
  mkdir -p \
    "${root}/Programs" \
    "${root}/Services" \
    "${root}/System/Compatibility/bin" \
    "${root}/System/Logs" \
    "${root}/System/Settings" \
    "${root}/System/State" \
    "${root}/Work"
}

zero="${stage}/zero"
make_skeleton "${zero}"
cp -a "${STRICT_ROOT}/Programs/BusyBox" "${zero}/Programs/"
cp -a "${STRICT_ROOT}/System/Compatibility/bin/." \
  "${zero}/System/Compatibility/bin/"

tar -C "${zero}" -cf - . | docker import \
  --change 'WORKDIR /Work' \
  --change 'ENV PATH=/System/Compatibility/bin:/Programs/BusyBox/current/Commands' \
  --change 'CMD ["/Programs/BusyBox/current/Commands/busybox", "sh"]' \
  - "${BUSYBOX_IMAGE}" >/dev/null

docker run --rm "${BUSYBOX_IMAGE}" "${BUSYBOX}" sh -ec '
  test ! -e /bin
  test ! -e /usr
  test ! -e /lib
  test ! -e /lib64
  echo auzix-container-zero-ok
'

one="${stage}/one"
cp -a "${zero}" "${one}"
cp -a "${PORT_ROOT}/Programs/Nginx" "${one}/Programs/"
cp -a "${PORT_ROOT}/Services/Nginx" "${one}/Services/"
cp -a "${PORT_ROOT}/System/Settings/Nginx" "${one}/System/Settings/"
mkdir -p "${one}/System/Logs/Nginx" "${one}/System/State/Nginx"
cp -a "${PORT_ROOT}/Work/Nginx" "${one}/Work/"
chmod 0750 \
  "${one}/System/Logs/Nginx" \
  "${one}/System/State/Nginx" \
  "${one}/Work/Nginx/"*

tar --owner=65534 --group=65534 -C "${one}" -cf - . | docker import \
  --change 'WORKDIR /Work' \
  --change 'USER 65534:65534' \
  --change 'EXPOSE 8080' \
  --change 'ENV PATH=/System/Compatibility/bin:/Programs/BusyBox/current/Commands:/Programs/Nginx/current/Commands' \
  --change 'CMD ["/Services/Nginx/run"]' \
  - "${NGINX_IMAGE}" >/dev/null

docker run --rm "${NGINX_IMAGE}" \
  /Programs/Nginx/current/Commands/nginx -t \
  -c /System/Settings/Nginx/nginx.conf -p /

container_id="$(docker run -d -p 127.0.0.1::8080 "${NGINX_IMAGE}")"
stop_container() {
  docker rm -f "${container_id}" >/dev/null 2>&1 || true
}
trap 'stop_container; cleanup' EXIT
host_port="$(docker port "${container_id}" 8080/tcp | awk -F: 'NR == 1 {print $NF}')"
for _attempt in 1 2 3 4 5; do
  if wget -qO- "http://127.0.0.1:${host_port}/" | grep -F 'AUZiX container one' >/dev/null; then
    printf 'auzix-container-one-ok port=%s\n' "${host_port}"
    break
  fi
  sleep 1
done
wget -qO- "http://127.0.0.1:${host_port}/" | grep -F 'AUZiX container one' >/dev/null
stop_container
trap cleanup EXIT

for image in "${BUSYBOX_IMAGE}" "${NGINX_IMAGE}"; do
  docker image inspect --format '{{index .RepoTags 0}} {{.Size}} bytes' "${image}"
done
