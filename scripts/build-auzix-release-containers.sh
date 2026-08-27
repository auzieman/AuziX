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
PACKAGE_REPO_URL="${AUZIX_PACKAGE_REPO_URL:-http://192.168.1.10/auzix/repo}"
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
cp "${ROOT_DIR}/docker/release/pre-hdd/packages.list" "${WORK}/pre-hdd/packages.list"

# Image zero: the canonical AUZiX substrate plus the newly packaged BusyBox.
for path in System Programs/BusyBox Programs/Busybox; do
  copy_tree "${PREPARED_ROOT}/${path}" "${WORK}/zero-busybox/root/${path}"
done
mkdir -p "${WORK}/zero-busybox/root"/{Services,Work,Users/root}
# The prepared workstation root contains compatibility links for every package.
# Image zero must advertise only commands its BusyBox payload actually owns.
for compat_dir in bin sbin usr/bin usr/sbin; do
  directory="${WORK}/zero-busybox/root/System/Compatibility/${compat_dir}"
  [[ -d "${directory}" ]] || continue
  while IFS= read -r entry; do
    target="$(readlink "${entry}" 2>/dev/null || true)"
    case "${target}" in
      /Programs/BusyBox/*|/Programs/Busybox/*) ;;
      *) rm -f "${entry}" ;;
    esac
  done < <(find "${directory}" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) -print)
done

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
    # Debian dependency graphs contain valid strongly connected components.
    # An active node is already scheduled by its caller; do not recurse twice.
    if key in active: return
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

# Promote nginx's packaged configuration into the AUZiX service contract.
nginx_common="$(find "${WORK}/one-nginx/root/Programs/NginxCommon" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[[ -n "${nginx_common}" && -s "${nginx_common}/RootFS/etc/nginx/mime.types" ]] \
  || fail "packaged NginxCommon configuration is missing"
mkdir -p \
  "${WORK}/one-nginx/root/Services/Nginx/Site" \
  "${WORK}/one-nginx/root/System/State/Nginx" \
  "${WORK}/one-nginx/root/System/Logs/Nginx" \
  "${WORK}/one-nginx/root/Work/Nginx/ClientBody" \
  "${WORK}/one-nginx/root/Work/Nginx/Proxy" \
  "${WORK}/one-nginx/root/Work/Nginx/FastCGI" \
  "${WORK}/one-nginx/root/Work/Nginx/UWSGI" \
  "${WORK}/one-nginx/root/Work/Nginx/SCGI" \
  "${WORK}/one-nginx/root/Work/Temp"
cp -a "${nginx_common}/RootFS/etc/nginx/mime.types" \
  "${WORK}/one-nginx/root/Services/Nginx/mime.types"
printf '%s\n' \
  'daemon off;' \
  'pid /System/State/Nginx/nginx.pid;' \
  'error_log stderr notice;' \
  'events { worker_connections 256; }' \
  'http {' \
  '  include /Services/Nginx/mime.types;' \
  '  default_type application/octet-stream;' \
  '  access_log /System/Logs/Nginx/access.log;' \
  '  client_body_temp_path /Work/Nginx/ClientBody;' \
  '  proxy_temp_path /Work/Nginx/Proxy;' \
  '  fastcgi_temp_path /Work/Nginx/FastCGI;' \
  '  uwsgi_temp_path /Work/Nginx/UWSGI;' \
  '  scgi_temp_path /Work/Nginx/SCGI;' \
  '  server { listen 8080; server_name _; root /Services/Nginx/Site; location / { try_files $uri $uri/ =404; } }' \
  '}' >"${WORK}/one-nginx/root/Services/Nginx/nginx.conf"
printf '%s\n' '<!doctype html><title>AUZiX Nginx</title><h1>AUZiX container one</h1><p>BusyBox is zero; Nginx is one.</p>' \
  >"${WORK}/one-nginx/root/Services/Nginx/Site/index.html"
printf '%s\n' \
  '#!/Programs/BusyBox/current/Commands/busybox sh' \
  'exec /Programs/Nginx/current/Commands/nginx -c /Services/Nginx/nginx.conf -p /' \
  >"${WORK}/one-nginx/root/Services/Nginx/run"
chmod 0755 "${WORK}/one-nginx/root/Services/Nginx/run"
chown -R 65534:65534 \
  "${WORK}/one-nginx/root/Services/Nginx" \
  "${WORK}/one-nginx/root/System/State/Nginx" \
  "${WORK}/one-nginx/root/System/Logs/Nginx" \
  "${WORK}/one-nginx/root/Work/Nginx" \
  "${WORK}/one-nginx/root/Work/Temp"

docker build --pull=false -t "${BUSYBOX_IMAGE}" "${WORK}/zero-busybox"
docker run --rm "${BUSYBOX_IMAGE}" /Programs/Busybox/current/Commands/busybox sh -ec \
  'test -x /System/Libraries/Runtime/glibc/libc.so.6; test ! -e /usr; echo auzix-zero-ok'
docker rm -f auzix-zero-busybox >/dev/null 2>&1 || true
docker run -d --name auzix-zero-busybox "${BUSYBOX_IMAGE}" \
  /Programs/Busybox/current/Commands/busybox sh -c 'while :; do sleep 3600; done' >/dev/null

docker build --pull=false --build-arg "BASE_IMAGE=${BUSYBOX_IMAGE}" -t "${NGINX_IMAGE}" "${WORK}/one-nginx"
docker run --rm "${NGINX_IMAGE}" /Programs/Nginx/current/Commands/nginx -t \
  -c /Services/Nginx/nginx.conf -p /
docker rm -f auzix-one-nginx >/dev/null 2>&1 || true
docker run -d --name auzix-one-nginx "${NGINX_IMAGE}" >/dev/null

# Image monster: exact prepared package-built root used by the HDD lane.  Stage
# it only after the two small images pass so they remain available immediately.
copy_tree "${PREPARED_ROOT}" "${WORK}/pre-hdd/root"
python3 - "${INDEX}" "${WORK}/pre-hdd/packages.list" "${WORK}/pre-hdd-order.txt" <<'PY'
import json, sys
index, roots_file, output = sys.argv[1:]
packages = json.load(open(index)).get("packages", [])
by_name = {p["name"].casefold(): p for p in packages}
roots = [line.strip() for line in open(roots_file) if line.strip() and not line.lstrip().startswith("#")]
seen, active, ordered = set(), set(), []
def visit(name):
    key = name.casefold()
    if key in seen or key in active: return
    package = by_name.get(key)
    if package is None: raise SystemExit(f"missing frozen dependency {name}")
    active.add(key)
    for dependency in package.get("depends") or []: visit(dependency)
    active.remove(key); seen.add(key); ordered.append(package["package"])
for root in roots: visit(root)
open(output, "w").write("".join(p + "\n" for p in ordered))
print(f"pre-hdd closure packages={len(ordered)} roots={len(roots)}")
PY
while IFS= read -r archive; do
  [[ -n "${archive}" ]] || continue
  tar --numeric-owner -xzf "${RELEASE_ROOT}/repo/packages/${archive}" -C "${WORK}/pre-hdd/root"
done <"${WORK}/pre-hdd-order.txt"
mkdir -p "${WORK}/pre-hdd/root/Users/auzix" "${WORK}/pre-hdd/root/Work/Temp" "${WORK}/pre-hdd/root/Work/Validation"
mkdir -p "${WORK}/pre-hdd/root/System/Settings/packages"
printf '%s\n' "${PACKAGE_REPO_URL}" >"${WORK}/pre-hdd/root/System/Settings/packages/repositories.conf"
chown 1000:1000 "${WORK}/pre-hdd/root/Users/auzix" "${WORK}/pre-hdd/root/Work/Temp" "${WORK}/pre-hdd/root/Work/Validation"
docker build --pull=false -t "${MONSTER_IMAGE}" "${WORK}/pre-hdd"
monster_run() {
  docker run --rm \
    --user 1000:1000 \
    -e HOME=/Users/auzix -e USER=auzix -e LOGNAME=auzix \
    -e TERM=xterm-256color \
    "${MONSTER_IMAGE}" "$@"
}
docker run --rm "${MONSTER_IMAGE}" /Programs/Busybox/current/Commands/busybox sh -ec '
  test -s /System/State/packages/installed.json
  test -x /System/Libraries/Runtime/glibc/libc.so.6
  test -x /Programs/Glances/current/Commands/glances
  test -x /Programs/Htop/current/Commands/htop
  test -x /Programs/Python313Minimal/current/Commands/python3.13
  test -s /Programs/NcursesBase/current/RootFS/usr/share/terminfo/x/xterm-256color
'
monster_run /Programs/Python313Minimal/current/Commands/python3.13 -c \
  'import curses, ssl, sqlite3; print(ssl.OPENSSL_VERSION)'
monster_run /Programs/Glances/current/Commands/glances --version
monster_run /Programs/Htop/current/Commands/htop --version
monster_run /Programs/AuzixPackageTools/current/Commands/auzix-pkg refresh
monster_run /Programs/Busybox/current/Commands/busybox sh -ec '
  printf "AUZiX LibreOffice conversion proof\n" > /Work/Validation/input.txt
  lowriter --headless --convert-to pdf --outdir /Work/Validation /Work/Validation/input.txt
  test -s /Work/Validation/input.pdf
'
python3 - "${WORK}/pre-hdd/root" <<'PY'
import configparser, shlex, sys
from pathlib import Path
root = Path(sys.argv[1])
failures = []
for desktop in root.glob("Programs/*/*/RootFS/usr/share/applications/*.desktop"):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        parser.read(desktop, encoding="utf-8")
        value = parser.get("Desktop Entry", "Exec", fallback="").strip()
        if not value:
            continue
        command = shlex.split(value)[0]
    except Exception as error:
        failures.append(f"{desktop}: parse error: {error}")
        continue
    if command.startswith("/"):
        candidates = [root / command.lstrip("/")]
    else:
        candidates = list(root.glob(f"Programs/*/current/Commands/{command}"))
    if not any(path.exists() for path in candidates):
        failures.append(f"{desktop}: unresolved Exec={command}")
if failures:
    print("\n".join(failures[:50]), file=sys.stderr)
    raise SystemExit(f"desktop launcher failures={len(failures)}")
PY
log "pre-HDD runtime intent passed for root and uid=1000"
docker rm -f auzix-pre-hdd >/dev/null 2>&1 || true
docker run -d --name auzix-pre-hdd "${MONSTER_IMAGE}" \
  /Programs/Busybox/current/Commands/busybox sh -c 'while :; do sleep 3600; done' >/dev/null

for tuple in "busybox:${BUSYBOX_IMAGE}" "nginx:${NGINX_IMAGE}" "pre-hdd:${MONSTER_IMAGE}"; do
  name="${tuple%%:*}"; image="${tuple#*:}"
  docker image inspect --format '{{.Id}} {{.Size}}' "${image}" | \
    awk -v name="${name}" -v image="${image}" -v release="${RELEASE_ID}" \
      '{printf "format=auzix-container-receipt-v1\nname=%s\nimage=%s\nimage_id=%s\nsize=%s\nrelease_id=%s\nstatus=pass\n",name,image,$1,$2,release}' \
      >"${WORK}/receipts/${name}.receipt"
done

log "PASS run=${RUN_ID} work=${WORK}"
log "images=${BUSYBOX_IMAGE} ${NGINX_IMAGE} ${MONSTER_IMAGE}"
