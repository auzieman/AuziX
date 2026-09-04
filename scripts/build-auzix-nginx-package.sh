#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/extended-ports/AuZiXRoot}"

mkdir -p \
  "${AUZIX_ROOT}/Programs" \
  "${AUZIX_ROOT}/Services/Nginx/Site" \
  "${AUZIX_ROOT}/System/Settings/Nginx" \
  "${AUZIX_ROOT}/System/State/Nginx" \
  "${AUZIX_ROOT}/System/Logs/Nginx" \
  "${AUZIX_ROOT}/Work/Nginx/ClientBody" \
  "${AUZIX_ROOT}/Work/Nginx/Proxy" \
  "${AUZIX_ROOT}/Work/Nginx/FastCGI" \
  "${AUZIX_ROOT}/Work/Nginx/UWSGI" \
  "${AUZIX_ROOT}/Work/Nginx/SCGI"

rm -rf "${AUZIX_ROOT}/Programs/Nginx"
find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
  -name 'Nginx-*.auzix.json' -delete 2>/dev/null || true

"${ROOT_DIR}/scripts/build-auzix-command-suite-package.sh" \
  "${AUZIX_ROOT}" "${ROOT_DIR}/packages/nginx.command-suite.json"

nginx_version="$(basename "$(readlink "${AUZIX_ROOT}/Programs/Nginx/current")")"
install -m 0755 /dev/stdin \
  "${AUZIX_ROOT}/Programs/Nginx/${nginx_version}/Commands/nginx" <<'EOF'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
exec /Libraries/ld-linux-x86-64.so.2 \
  --library-path /Libraries:/Programs/Nginx/current/Libraries \
  /Programs/Nginx/current/Commands/nginx.real "$@"
EOF

install -m 0644 /etc/nginx/mime.types \
  "${AUZIX_ROOT}/System/Settings/Nginx/mime.types"

install -m 0644 /dev/stdin "${AUZIX_ROOT}/System/Settings/Nginx/nginx.conf" <<'EOF'
daemon off;
pid /System/State/Nginx/nginx.pid;
error_log stderr notice;

events {
  worker_connections 256;
}

http {
  include /System/Settings/Nginx/mime.types;
  default_type application/octet-stream;
  access_log /System/Logs/Nginx/access.log;
  client_body_temp_path /Work/Nginx/ClientBody;
  proxy_temp_path /Work/Nginx/Proxy;
  fastcgi_temp_path /Work/Nginx/FastCGI;
  uwsgi_temp_path /Work/Nginx/UWSGI;
  scgi_temp_path /Work/Nginx/SCGI;

  server {
    listen 8443 ssl;
    server_name auzix-repo.test;
    ssl_certificate /System/Settings/Nginx/TLS/server.crt;
    ssl_certificate_key /System/Settings/Nginx/TLS/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    root /Repository;
    location / {
      try_files $uri $uri/ =404;
    }
  }
}
EOF

install -m 0644 /dev/stdin "${AUZIX_ROOT}/Services/Nginx/Site/index.html" <<'EOF'
<!doctype html>
<html><head><title>AUZiX Nginx</title></head>
<body><h1>AUZiX APK repository</h1><p>Served by the package-installed one-nginx image.</p></body></html>
EOF

# Keep the historical /Services/Nginx/nginx.conf path as well as Settings.
# An older edge image shipped the binary but forgot this file.
install -m 0644 "${AUZIX_ROOT}/System/Settings/Nginx/nginx.conf" \
  "${AUZIX_ROOT}/Services/Nginx/nginx.conf"

install -m 0755 /dev/stdin "${AUZIX_ROOT}/Services/Nginx/run" <<'EOF'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -eu
test -s /System/Settings/Nginx/TLS/server.crt
test -s /System/Settings/Nginx/TLS/server.key
test -s /Repository/x86_64/APKINDEX.tar.gz
test -e /etc/passwd || ln -s /System/Settings/passwd /etc/passwd
test -e /etc/group || ln -s /System/Settings/group /etc/group
exec /Programs/Nginx/current/Commands/nginx \
  -c /System/Settings/Nginx/nginx.conf \
  -p /
EOF

printf '[auzix-nginx] package and service payload built under %s\n' "${AUZIX_ROOT}"
