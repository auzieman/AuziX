#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT_INPUT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
mkdir -p "${AUZIX_ROOT_INPUT}"
AUZIX_ROOT="$(cd "${AUZIX_ROOT_INPUT}" && pwd)"
WORK_DIR="${ROOT_DIR}/out/auzix-packages/ca-certificates"
EXTRACT_DIR="${TMPDIR:-/tmp}/auzix-ca-certificates-extract.$$"
PACKAGE_DB="${AUZIX_ROOT}/System/PackageDB"
SSL_CERTS="${AUZIX_ROOT}/System/Compatibility/etc/ssl/certs"
SSL_SHARE="${AUZIX_ROOT}/System/Compatibility/usr/share/ca-certificates"
PKI_CERTS="${AUZIX_ROOT}/System/Settings/pki/tls/certs"
SETTINGS_SSL="${AUZIX_ROOT}/System/Settings/ssl"
VERSION="${AUZIX_CA_CERTIFICATES_VERSION:-}"

cleanup() {
  rm -rf "${EXTRACT_DIR}"
}
trap cleanup EXIT

mkdir -p "${SSL_CERTS}" "${SSL_SHARE}" "${PKI_CERTS}" "${PACKAGE_DB}" \
  "${WORK_DIR}/debs" "${EXTRACT_DIR}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

detect_version() {
  local version
  version="$(apt-cache show ca-certificates 2>/dev/null | awk '/^Version:/ {print $2; exit}')"
  if [[ -n "${version}" ]]; then
    printf '%s\n' "${version}"
  else
    printf 'system\n'
  fi
}

copy_cert_tree_if_present() {
  local source="$1"
  local target="$2"
  [[ -e "${source}" ]] || return 0
  rm -rf "${target}"
  mkdir -p "${target}"
  (
    cd "${source}"
    while IFS= read -r cert; do
      install -D -m 0644 "${cert}" "${target}/${cert#./}"
    done < <(find . -type f -name '*.crt' -print | sort)
  )
}

copy_bundle_if_present() {
  local source="$1"
  local target="$2"
  [[ -s "${source}" ]] || return 0
  install -D -m 0644 "${source}" "${target}"
}

downloaded_deb=0
if command -v apt-get >/dev/null 2>&1 && command -v dpkg-deb >/dev/null 2>&1; then
  rm -rf "${WORK_DIR}/debs" "${EXTRACT_DIR}"
  mkdir -p "${WORK_DIR}/debs" "${EXTRACT_DIR}"
  (
    cd "${WORK_DIR}/debs"
    apt-get download ca-certificates >/dev/null
  ) && downloaded_deb=1 || downloaded_deb=0
  if [[ "${downloaded_deb}" == "1" ]] && compgen -G "${WORK_DIR}/debs/*.deb" >/dev/null; then
    for deb in "${WORK_DIR}"/debs/*.deb; do
      dpkg-deb -x "${deb}" "${EXTRACT_DIR}"
    done
    VERSION="${VERSION:-$(detect_version)-auzix1}"
    copy_cert_tree_if_present "${EXTRACT_DIR}/etc/ssl/certs" "${SSL_CERTS}"
    copy_cert_tree_if_present "${EXTRACT_DIR}/usr/share/ca-certificates" "${SSL_SHARE}"
    if [[ ! -s "${SSL_CERTS}/ca-certificates.crt" && -d "${SSL_SHARE}/mozilla" ]]; then
      find "${SSL_SHARE}/mozilla" -maxdepth 1 -type f -name '*.crt' -print |
        sort |
        while IFS= read -r cert; do
          cat "${cert}"
          printf '\n'
        done >"${SSL_CERTS}/ca-certificates.crt"
    fi
  fi
fi

if [[ "${downloaded_deb}" != "1" ]]; then
  printf '[ca-certificates] apt download unavailable; falling back to builder trust store\n' >&2
  VERSION="${VERSION:-system-auzix1}"
  if [[ ! -s "${SSL_CERTS}/ca-certificates.crt" ]]; then
    copy_cert_tree_if_present /etc/ssl/certs "${SSL_CERTS}"
    copy_bundle_if_present /etc/ssl/certs/ca-certificates.crt "${SSL_CERTS}/ca-certificates.crt"
    copy_bundle_if_present /etc/ssl/cert.pem "${SSL_CERTS}/ca-certificates.crt"
  fi

  if [[ -d /usr/share/ca-certificates && ! -d "${SSL_SHARE}/mozilla" ]]; then
    copy_cert_tree_if_present /usr/share/ca-certificates "${SSL_SHARE}"
  fi
  if [[ ! -s "${SSL_CERTS}/ca-certificates.crt" && -d "${SSL_SHARE}/mozilla" ]]; then
    find "${SSL_SHARE}/mozilla" -maxdepth 1 -type f -name '*.crt' -print |
      sort |
      while IFS= read -r cert; do
        cat "${cert}"
        printf '\n'
      done >"${SSL_CERTS}/ca-certificates.crt"
  fi
fi

if [[ ! -s "${SSL_CERTS}/ca-certificates.crt" ]]; then
  printf 'CA bundle missing: %s\n' "${SSL_CERTS}/ca-certificates.crt" >&2
  exit 1
fi

rm -f "${PACKAGE_DB}"/CACerts-*.auzix.json

ln -sfn /System/Compatibility/etc/ssl/certs/ca-certificates.crt \
  "${AUZIX_ROOT}/System/Compatibility/etc/ssl/cert.pem"
rm -rf "${SETTINGS_SSL}"
ln -sfn /System/Compatibility/etc/ssl "${SETTINGS_SSL}"
ln -sfn /System/Compatibility/etc/ssl/certs/ca-certificates.crt \
  "${PKI_CERTS}/ca-bundle.crt"

cat >"${PACKAGE_DB}/CACerts-${VERSION}.auzix.json" <<EOF
{
  "name": "CACerts",
  "version": "${VERSION}",
  "kind": "system",
  "migration_stage": "first-pass-debian-data-port",
  "description": "AUZiX trust-store contract for TLS clients that expect Debian-style /etc/ssl and Fedora/RHEL-style /etc/pki CA bundle paths.",
  "source": {
    "type": "debian-binary",
    "suite": "trixie",
    "package": "ca-certificates",
    "graduation": "upstream-source-or-mozilla-certdata"
  },
  "paths": {
    "certificates": "/System/Compatibility/etc/ssl/certs",
    "debian_bundle": "/System/Compatibility/etc/ssl/certs/ca-certificates.crt",
    "debian_etc_alias": "/System/Settings/ssl -> /System/Compatibility/etc/ssl",
    "fedora_bundle": "/System/Settings/pki/tls/certs/ca-bundle.crt",
    "openssl_usr_lib_bundle": "/System/Compatibility/usr/lib/ssl/cert.pem via /System/Compatibility/usr/lib/ssl -> /System/Compatibility/etc/ssl",
    "share": "/System/Compatibility/usr/share/ca-certificates"
  },
  "settings": [
    "/System/Compatibility/etc/ssl/certs",
    "/System/Compatibility/etc/ssl/cert.pem",
    "/System/Settings/ssl",
    "/System/Settings/pki/tls/certs/ca-bundle.crt",
    "/System/Compatibility/usr/share/ca-certificates"
  ],
  "commands": [],
  "compatibility_exports": [
    "/System/Compatibility/etc/ssl/certs",
    "/System/Compatibility/etc/ssl/cert.pem",
    "/System/Settings/ssl",
    "/System/Settings/pki/tls/certs/ca-bundle.crt",
    "/System/Compatibility/usr/share/ca-certificates"
  ],
  "validation": {
    "smoke_commands": [
      "test -s /System/Compatibility/etc/ssl/certs/ca-certificates.crt",
      "test -s /System/Settings/ssl/certs/ca-certificates.crt",
      "test -e /System/Settings/pki/tls/certs/ca-bundle.crt"
    ]
  },
  "notes": "Flatpak/libcurl on the Debian-built worker checks /etc/pki/tls/certs/ca-bundle.crt; /etc maps to /System/Settings on AUZiX."
}
EOF

printf '[ca-certificates] staged CACerts %s\n' "${VERSION}"
