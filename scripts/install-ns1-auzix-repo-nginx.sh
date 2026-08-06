#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${ROOT_DIR}/ops/nginx/ns1-bkc-pxe.conf"
TARGET="/etc/nginx/conf.d/bkc-pxe.conf"

[[ -f "${SOURCE}" ]] || { echo "Missing ${SOURCE}" >&2; exit 1; }
[[ -s /srv/http/auzix/repo/index.json ]] || {
  echo 'Missing /srv/http/auzix/repo/index.json' >&2
  exit 1
}

install -m 0644 "${SOURCE}" "${TARGET}"
if command -v semanage >/dev/null 2>&1; then
  semanage fcontext -a -t httpd_sys_content_t '/srv/http/auzix(/.*)?' 2>/dev/null ||
    semanage fcontext -m -t httpd_sys_content_t '/srv/http/auzix(/.*)?'
  restorecon -RF /srv/http/auzix
fi
nginx -t
systemctl reload nginx
curl -fsS http://127.0.0.1/auzix/repo/index.json >/dev/null
echo 'PASS: ns1 AuziX repository is published'
