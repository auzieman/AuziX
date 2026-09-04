#!/Programs/BusyBox/current/Commands/busybox sh
set -eu

test -e /etc/apk || ln -s /System/Settings/apk /etc/apk

set --
while IFS= read -r pattern; do
  case "$pattern" in
    ''|\#*) continue ;;
  esac
  matched=0
  for archive in /Repository/x86_64/$pattern; do
    test -f "$archive" || continue
    matched=1
    set -- "$@" "$archive"
  done
  if test "$matched" -eq 0; then
    printf 'one-nginx: no APK matched %s\n' "$pattern" >&2
    exit 1
  fi
done </System/Settings/apk/one-nginx.packages

# Factory signs the index, not individual artifacts. Edge builds install by
# filename until a signed APKINDEX exists for netinstall. Keep maintainer
# scripts (pre/inst/post). Do not COPY program trees into /Programs.
/Programs/ApkTools/current/Commands/apk add --allow-untrusted --no-network "$@"

test -s /System/State/apk/db/installed

# Nginx defaults to user nobody when started as root. Keep any existing
# accounts from zero and only add the service identity if it is missing.
if ! grep -q '^nobody:' /System/Settings/passwd 2>/dev/null; then
  printf 'nobody:x:65534:65534:nobody:/nonexistent:/sbin/nologin\n' \
    >> /System/Settings/passwd
fi
if ! grep -q '^nogroup:' /System/Settings/group 2>/dev/null; then
  printf 'nogroup:x:65534:nobody\n' >> /System/Settings/group
fi
test -e /etc/passwd || ln -s /System/Settings/passwd /etc/passwd
test -e /etc/group || ln -s /System/Settings/group /etc/group

mkdir -p \
  /Services/Nginx/Site \
  /System/Settings/Nginx \
  /System/State/Nginx \
  /System/Logs/Nginx \
  /Work/Nginx/ClientBody \
  /Work/Nginx/Proxy \
  /Work/Nginx/FastCGI \
  /Work/Nginx/UWSGI \
  /Work/Nginx/SCGI

test -s /System/Settings/Nginx/nginx.conf
test -s /System/Settings/Nginx/TLS/server.crt
test -s /System/Settings/Nginx/TLS/server.key
test -s /Repository/x86_64/APKINDEX.tar.gz
test -s /Services/Nginx/nginx.conf
test -x /Services/Nginx/run
test -x /Programs/Nginx/current/Commands/nginx

rm -f /Work/install-one-nginx
