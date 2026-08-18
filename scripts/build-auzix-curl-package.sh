#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/auzix-library-policy.sh"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
WORK_DIR="${ROOT_DIR}/out/auzix-packages/curl"
APT_PACKAGES=(curl ca-certificates)
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"
RUNTIME_USR="${AUZIX_ROOT}/System/Compatibility/usr"

log() {
  printf '[auzix-curl] %s\n' "$*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

detect_version() {
  local version
  version="$(apt-cache show curl 2>/dev/null | awk '/^Version:/ {print $2; exit}')"
  if [[ -z "${version}" ]]; then
    printf 'host\n'
  else
    printf '%s\n' "${version}"
  fi
}

copy_dep_path() {
  local dep="$1"
  [[ -e "${dep}" ]] || return 0
  case "${dep}" in
    /lib64/*)
      install -D -m 0755 "${dep}" "${RUNTIME_LIB64}/$(basename "${dep}")"
      auzix_copy_app_private_library "${dep}" "${CURL_PROGRAM}/Libraries/$(basename "${dep}")"
      ;;
    /lib/x86_64-linux-gnu/*|/usr/lib/x86_64-linux-gnu/*)
      install -D -m 0755 "${dep}" "${RUNTIME_LIB}/$(basename "${dep}")"
      auzix_copy_app_private_library "${dep}" "${CURL_PROGRAM}/Libraries/$(basename "${dep}")"
      ;;
    /usr/lib/*)
      install -D -m 0755 "${dep}" "${RUNTIME_USR}/lib/${dep#/usr/lib/}"
      auzix_copy_app_private_library "${dep}" "${CURL_PROGRAM}/Libraries/${dep#/usr/lib/}"
      ;;
    *)
      install -D -m 0755 "${dep}" "${AUZIX_ROOT}${dep}"
      ;;
  esac
}

copy_runtime_deps() {
  local binary="$1"
  local dep
  if ! file "${binary}" | grep -q 'ELF'; then
    return 0
  fi
  ldd "${binary}" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' | sort -u |
  while IFS= read -r dep; do
    copy_dep_path "${dep}"
  done
}

copy_dir_if_present() {
  local source="$1"
  local target="$2"
  [[ -e "${source}" ]] || return 0
  rm -rf "${target}"
  mkdir -p "$(dirname "${target}")"
  cp -a "${source}" "${target}"
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

require_cmd apt-get
require_cmd apt-cache
require_cmd dpkg-deb
require_cmd file
require_cmd install
require_cmd ldd

CURL_VERSION="${AUZIX_CURL_VERSION:-$(detect_version)}"
CURL_PROGRAM="${AUZIX_ROOT}/Programs/Curl/${CURL_VERSION}"

rm -rf "${WORK_DIR}" "${CURL_PROGRAM}"
mkdir -p "${WORK_DIR}/debs" "${WORK_DIR}/extract"

downloaded_debs=0
(
  cd "${WORK_DIR}/debs"
  apt-get download "${APT_PACKAGES[@]}" >/dev/null
) && downloaded_debs=1 || downloaded_debs=0

if [[ "${downloaded_debs}" == "1" ]] && compgen -G "${WORK_DIR}/debs/*.deb" >/dev/null; then
  for deb in "${WORK_DIR}"/debs/*.deb; do
    dpkg-deb -x "${deb}" "${WORK_DIR}/extract"
  done
else
  log "apt download unavailable; falling back to installed builder curl runtime"
  install -D -m 0755 /usr/bin/curl "${WORK_DIR}/extract/usr/bin/curl"
fi

if [[ ! -x "${WORK_DIR}/extract/usr/bin/curl" ]]; then
  printf 'curl binary not found in downloaded packages.\n' >&2
  exit 1
fi

mkdir -p \
  "${CURL_PROGRAM}/Commands" \
  "${CURL_PROGRAM}/Libraries" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${RUNTIME_USR}/bin" \
  "${RUNTIME_USR}/share/ca-certificates" \
  "${RUNTIME_USR}/lib/x86_64-linux-gnu" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}" \
  "${AUZIX_ROOT}/System/PackageDB"

install -D -m 0755 "${WORK_DIR}/extract/usr/bin/curl" "${CURL_PROGRAM}/Commands/curl.real"
copy_runtime_deps "${WORK_DIR}/extract/usr/bin/curl"

cat > "${CURL_PROGRAM}/Commands/curl" <<'EOF'
#!/System/Compatibility/bin/sh
set -eu

export SSL_CERT_DIR="${SSL_CERT_DIR:-/etc/ssl/certs}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
export CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-${SSL_CERT_FILE}}"
export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-${SSL_CERT_FILE}}"
export GCONV_PATH="${GCONV_PATH:-/usr/lib/x86_64-linux-gnu/gconv:/System/Compatibility/usr/lib/x86_64-linux-gnu/gconv:/System/Compatibility/lib/x86_64-linux-gnu/gconv}"
exec /System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2 \
  --library-path /System/Libraries:/System/Libraries/Runtime/glibc:/Programs/Curl/current/Libraries:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64 \
  /Programs/Curl/current/Commands/curl.real "$@"
EOF
chmod 0755 "${CURL_PROGRAM}/Commands/curl"

ln -sfn "/Programs/Curl/${CURL_VERSION}" "${AUZIX_ROOT}/Programs/Curl/current"
ln -sfn /Programs/Curl/current/Commands/curl "${AUZIX_ROOT}/System/Compatibility/bin/curl"
ln -sfn /Programs/Curl/current/Commands/curl "${RUNTIME_USR}/bin/curl"

copy_dir_if_present /etc/ssl/certs "${AUZIX_ROOT}/System/Compatibility/etc/ssl/certs"
copy_dir_if_present /usr/share/ca-certificates "${RUNTIME_USR}/share/ca-certificates"
copy_dir_if_present /usr/lib/x86_64-linux-gnu/gconv "${RUNTIME_USR}/lib/x86_64-linux-gnu/gconv"
copy_dir_if_present /usr/lib/x86_64-linux-gnu/gconv "${RUNTIME_LIB}/gconv"
if [[ -x /usr/bin/iconv ]]; then
  install -D -m 0755 /usr/bin/iconv "${RUNTIME_USR}/bin/iconv"
  copy_runtime_deps /usr/bin/iconv
fi

cat > "${AUZIX_ROOT}/System/PackageDB/Curl-${CURL_VERSION}.auzix.json" <<EOF
{
  "name": "Curl",
  "version": "${CURL_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/Curl/${CURL_VERSION}",
  "paths": {
    "current": "/Programs/Curl/current",
    "certificates": "/System/Compatibility/etc/ssl/certs",
    "gconv": "/System/Compatibility/usr/lib/x86_64-linux-gnu/gconv"
  },
  "commands": [
    "/Programs/Curl/${CURL_VERSION}/Commands/curl",
    "/Programs/Curl/${CURL_VERSION}/Commands/curl.real"
  ],
  "runtime_libraries": [
    "/Programs/Curl/${CURL_VERSION}/Libraries"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/curl",
    "/System/Compatibility/usr/bin/curl",
    "/System/Compatibility/etc/ssl/certs",
    "/System/Compatibility/usr/share/ca-certificates",
    "/System/Compatibility/usr/lib/x86_64-linux-gnu/gconv"
  ],
  "notes": "curl plus CA and glibc gconv/iconv runtime plumbing for validating HTTPS before full browser packaging."
}
EOF

log "curl installed at ${CURL_PROGRAM}"
