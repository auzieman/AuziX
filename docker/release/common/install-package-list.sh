#!/Programs/BusyBox/current/Commands/busybox sh
set -eu

: "${AUZIX_PACKAGE_LIST:?set AUZIX_PACKAGE_LIST to the requested package list}"
: "${AUZIX_APK_REPOSITORY:?set AUZIX_APK_REPOSITORY to the signed repository URL}"
: "${SSL_CERT_FILE:?set SSL_CERT_FILE to the repository CA bundle}"

test -r "$AUZIX_PACKAGE_LIST"
test -r "$SSL_CERT_FILE"
test -e /etc/apk || ln -s /System/Settings/apk /etc/apk

packages=$(
  sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$AUZIX_PACKAGE_LIST"
)
test -n "$packages"

/Programs/ApkTools/current/Commands/apk add \
  --repository "$AUZIX_APK_REPOSITORY" \
  $packages

test -s /System/State/apk/db/installed
