#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/auzix-library-policy.sh"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
WORK_DIR="${ROOT_DIR}/out/auzix-packages/midori"
MIDORI_VERSION="${AUZIX_MIDORI_VERSION:-11.8}"
MIDORI_URL="${AUZIX_MIDORI_URL:-https://github.com/goastian/midori-desktop/releases/download/v${MIDORI_VERSION}/midori-${MIDORI_VERSION}.linux-x86_64.tar.xz}"
MIDORI_PROGRAM="${AUZIX_ROOT}/Programs/Midori/${MIDORI_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"
RUNTIME_USR="${AUZIX_ROOT}/System/Compatibility/usr"

log() {
  printf '[auzix-midori] %s\n' "$*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

require_cmd curl
require_cmd file
require_cmd install
require_cmd ldd
require_cmd tar

copy_dep_path() {
  local dep="$1"
  [[ -e "${dep}" ]] || return 0
  case "${dep}" in
    /lib64/*)
      install -D -m 0755 "${dep}" "${RUNTIME_LIB64}/$(basename "${dep}")"
      auzix_copy_app_private_library "${dep}" "${MIDORI_PROGRAM}/Libraries/$(basename "${dep}")"
      ;;
    /lib/x86_64-linux-gnu/*|/usr/lib/x86_64-linux-gnu/*)
      install -D -m 0755 "${dep}" "${RUNTIME_LIB}/$(basename "${dep}")"
      auzix_copy_app_private_library "${dep}" "${MIDORI_PROGRAM}/Libraries/$(basename "${dep}")"
      ;;
    /usr/lib/*)
      install -D -m 0755 "${dep}" "${RUNTIME_USR}/lib/${dep#/usr/lib/}"
      auzix_copy_app_private_library "${dep}" "${MIDORI_PROGRAM}/Libraries/${dep#/usr/lib/}"
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

rm -rf "${WORK_DIR}" "${MIDORI_PROGRAM}"
mkdir -p "${WORK_DIR}" "${MIDORI_PROGRAM}/Commands" "${MIDORI_PROGRAM}/Resources" "${MIDORI_PROGRAM}/Libraries" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Settings/browser" \
  "${RUNTIME_USR}/bin" \
  "${RUNTIME_USR}/share/applications" \
  "${RUNTIME_USR}/share/pixmaps" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}" \
  "${AUZIX_ROOT}/System/PackageDB"

archive="${WORK_DIR}/midori-${MIDORI_VERSION}.linux-x86_64.tar.xz"
if [[ -n "${AUZIX_MIDORI_ARCHIVE:-}" ]]; then
  cp -f "${AUZIX_MIDORI_ARCHIVE}" "${archive}"
else
  curl -L --fail -o "${archive}" "${MIDORI_URL}"
fi

tar -xf "${archive}" -C "${WORK_DIR}"
if [[ ! -x "${WORK_DIR}/midori/midori" ]]; then
  printf 'Midori executable not found in archive: %s\n' "${archive}" >&2
  exit 1
fi

mv "${WORK_DIR}/midori" "${MIDORI_PROGRAM}/Resources/midori"
find "${MIDORI_PROGRAM}/Resources/midori" -type d -exec chmod 0755 {} + 2>/dev/null || true
find "${MIDORI_PROGRAM}/Resources/midori" -type f -exec chmod 0644 {} + 2>/dev/null || true
find "${MIDORI_PROGRAM}/Resources/midori" -type f \
  \( -name midori -o -name midori-bin -o -name updater -o -name crashhelper -o -name pingsender -o -name glxtest -o -name vaapitest -o -name tor -o -name conjure-client -o -name lyrebird \) \
  -exec chmod 0755 {} + 2>/dev/null || true
find "${MIDORI_PROGRAM}/Resources/midori" -type f -name '*.so' -exec chmod 0755 {} + 2>/dev/null || true
find "${MIDORI_PROGRAM}/Resources/midori" -type f 2>/dev/null |
while IFS= read -r file_path; do
  copy_runtime_deps "${file_path}" || true
done

nss_trust_module="${AUZIX_NSS_TRUST_MODULE:-}"
if [[ -z "${nss_trust_module}" ]]; then
  for candidate in \
    "${MIDORI_PROGRAM}/Libraries/nss/libnssckbi.so" \
    "${MIDORI_PROGRAM}/Libraries/libnssckbi.so" \
    "${RUNTIME_LIB}/nss/libnssckbi.so" \
    "${RUNTIME_LIB}/libnssckbi.so" \
    /usr/lib/x86_64-linux-gnu/libnssckbi.so \
    /usr/lib/x86_64-linux-gnu/nss/libnssckbi.so \
    /usr/lib64/libnssckbi.so \
    /usr/lib/libnssckbi.so; do
    if [[ -f "${candidate}" ]]; then
      nss_trust_module="${candidate}"
      break
    fi
  done
fi
if [[ -f "${nss_trust_module}" ]]; then
  install -m 0755 "${nss_trust_module}" \
    "${MIDORI_PROGRAM}/Resources/midori/libnssckbi.so"
else
  nss_work="${WORK_DIR}/nss"
  mkdir -p "${nss_work}/debs" "${nss_work}/extract"
  if command -v apt-get >/dev/null 2>&1 && command -v dpkg-deb >/dev/null 2>&1 && \
     (cd "${nss_work}/debs" && apt-get download libnss3 >/dev/null 2>&1); then
    for deb in "${nss_work}"/debs/*.deb; do
      [[ -e "${deb}" ]] || continue
      dpkg-deb -x "${deb}" "${nss_work}/extract"
    done
    for candidate in \
      "${nss_work}/extract/usr/lib/x86_64-linux-gnu/nss/libnssckbi.so" \
      "${nss_work}/extract/usr/lib/x86_64-linux-gnu/libnssckbi.so"; do
      if [[ -f "${candidate}" ]]; then
        install -m 0755 "${candidate}" \
          "${MIDORI_PROGRAM}/Resources/midori/libnssckbi.so"
        nss_trust_module="${candidate}"
        break
      fi
    done
  fi
  if [[ ! -f "${MIDORI_PROGRAM}/Resources/midori/libnssckbi.so" ]]; then
    log "NSS trust module not found; continuing with AUZiX CA bundle environment only"
  fi
fi

mkdir -p \
  "${MIDORI_PROGRAM}/Resources/midori/distribution" \
  "${MIDORI_PROGRAM}/Resources/midori/defaults/pref" \
  "${AUZIX_ROOT}/System/Settings/browser/midori-default-profile"

cat > "${MIDORI_PROGRAM}/Resources/midori/distribution/policies.json" <<'EOF'
{
  "policies": {
    "Certificates": {
      "ImportEnterpriseRoots": true
    },
    "DisableAppUpdate": true,
    "DisableTelemetry": true,
    "DontCheckDefaultBrowser": true,
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": "",
    "Homepage": {
      "URL": "https://auzietek.com",
      "Locked": false,
      "StartPage": "homepage"
    }
  }
}
EOF

cat > "${MIDORI_PROGRAM}/Resources/midori/defaults/pref/auzix-cert-policy.js" <<'EOF'
// AUZiX live/install media use a relocated CA bundle.  Firefox-family/NSS
// browsers do not reliably honor SSL_CERT_FILE, so keep browser-native trust
// policy explicit and visible in the package payload.
pref("security.enterprise_roots.enabled", true);
pref("security.osclientcerts.autoload", true);
pref("browser.shell.checkDefaultBrowser", false);
pref("browser.startup.homepage_override.mstone", "ignore");
pref("browser.aboutwelcome.enabled", false);
pref("browser.startup.homepage", "https://auzietek.com|https://linux-users.auzietek.com/post/auzix-alpha-install-field-note?page=1&page_size=100&tag=linux&theme=linux-pro&lane=linux#article-start");
pref("browser.startup.page", 1);
pref("browser.newtabpage.enabled", false);
pref("browser.newtabpage.activity-stream.feeds.topsites", false);
pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
pref("browser.newtabpage.activity-stream.showSponsored", false);
pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
pref("trailhead.firstrun.didSeeAboutWelcome", true);
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("app.update.enabled", false);
EOF

cat > "${AUZIX_ROOT}/System/Settings/browser/midori-default-profile/user.js" <<'EOF'
user_pref("security.enterprise_roots.enabled", true);
user_pref("security.osclientcerts.autoload", true);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.homepage", "https://auzietek.com|https://linux-users.auzietek.com/post/auzix-alpha-install-field-note?page=1&page_size=100&tag=linux&theme=linux-pro&lane=linux#article-start");
user_pref("browser.startup.page", 1);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("app.update.enabled", false);
EOF
chmod 0644 \
  "${MIDORI_PROGRAM}/Resources/midori/distribution/policies.json" \
  "${MIDORI_PROGRAM}/Resources/midori/defaults/pref/auzix-cert-policy.js" \
  "${AUZIX_ROOT}/System/Settings/browser/midori-default-profile/user.js"

ca_bundle="${AUZIX_ROOT}/System/Compatibility/etc/ssl/certs/ca-certificates.crt"
profile_dir="${AUZIX_ROOT}/System/Settings/browser/midori-default-profile"
if command -v certutil >/dev/null 2>&1 && [[ -s "${ca_bundle}" ]]; then
  cert_work="${WORK_DIR}/certs"
  rm -rf "${cert_work}"
  mkdir -p "${cert_work}"
  certutil -N -d "sql:${profile_dir}" --empty-password >/dev/null 2>&1 || true
  awk '
    /-----BEGIN CERTIFICATE-----/ { n++; out=sprintf("'"${cert_work}"'/cert-%04d.pem", n) }
    out { print > out }
    /-----END CERTIFICATE-----/ { close(out); out="" }
  ' "${ca_bundle}"
  imported=0
  for cert in "${cert_work}"/cert-*.pem; do
    [[ -s "${cert}" ]] || continue
    imported=$((imported + 1))
    certutil -A -d "sql:${profile_dir}" \
      -n "AUZiX Root ${imported}" \
      -t "C,," \
      -i "${cert}" >/dev/null 2>&1 || true
  done
  if [[ -s "${profile_dir}/cert9.db" ]]; then
    log "Seeded Midori NSS trust DB with ${imported} CA entries"
  fi
else
  log "certutil unavailable; relying on Midori policy/preferences and bundled NSS trust module"
fi
find "${profile_dir}" -type f -exec chmod 0644 {} + 2>/dev/null || true

live_profile_dir="${AUZIX_ROOT}/Users/auzix/.midori"
if [[ -d "${AUZIX_ROOT}/Users/auzix" ]]; then
  mkdir -p "${live_profile_dir}"
  cp -a "${profile_dir}/." "${live_profile_dir}/"
  find "${live_profile_dir}" -type d -exec chmod 0755 {} + 2>/dev/null || true
  find "${live_profile_dir}" -type f -exec chmod 0644 {} + 2>/dev/null || true
  chown -R 1000:1000 "${live_profile_dir}" 2>/dev/null || true
fi

cat > "${MIDORI_PROGRAM}/Commands/midori" <<'EOF'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -eu

export HOME="${HOME:-/Users/auzix}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/System/Compatibility/usr/share:/usr/share}"
export GDK_BACKEND="${GDK_BACKEND:-x11}"
export MOZ_ENABLE_WAYLAND="${MOZ_ENABLE_WAYLAND:-0}"
export MOZ_WEBRENDER="${MOZ_WEBRENDER:-0}"
export MOZ_USE_XINPUT2="${MOZ_USE_XINPUT2:-1}"
export MOZ_DBUS_REMOTE="${MOZ_DBUS_REMOTE:-1}"
export MOZ_LEGACY_PROFILES="${MOZ_LEGACY_PROFILES:-1}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export SSL_CERT_DIR="${SSL_CERT_DIR:-/System/Compatibility/etc/ssl/certs}"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/System/Compatibility/etc/ssl/certs/ca-certificates.crt}"
export CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-${SSL_CERT_FILE}}"
export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-${SSL_CERT_FILE}}"
export NSS_DEFAULT_DB_TYPE="${NSS_DEFAULT_DB_TYPE:-sql}"
export GCONV_PATH="${GCONV_PATH:-/usr/lib/x86_64-linux-gnu/gconv:/System/Compatibility/usr/lib/x86_64-linux-gnu/gconv:/System/Compatibility/lib/x86_64-linux-gnu/gconv}"
export LD_LIBRARY_PATH="/System/Libraries:/System/Libraries/Runtime/glibc:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu/nss:/System/Compatibility/lib64:/Programs/Midori/current/Resources/midori:/Programs/Midori/current/Libraries${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

mkdir -p "${XDG_RUNTIME_DIR}" "${XDG_CACHE_HOME}" "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${HOME}/.midori" 2>/dev/null || true
chmod 0700 "${XDG_RUNTIME_DIR}" 2>/dev/null || true
if [ -s /System/Settings/browser/midori-default-profile/user.js ] &&
   [ ! -s "${HOME}/.midori/user.js" ]; then
  cp -R /System/Settings/browser/midori-default-profile/. "${HOME}/.midori/" 2>/dev/null || true
  chmod -R u+rwX "${HOME}/.midori" 2>/dev/null || true
fi
if [ ! -w "${XDG_CACHE_HOME}" ] || [ ! -w "${XDG_CONFIG_HOME}" ] ||
   [ ! -w "${XDG_DATA_HOME}" ] || [ ! -w "${HOME}/.midori" ]; then
  echo "Midori profile directories are not writable by $(id -un 2>/dev/null || echo current-user)." >&2
  echo "Restart the session or run /System/Tools/repair-e-state as root, then start Midori again." >&2
  exit 1
fi

cd /Programs/Midori/current/Resources/midori
if [ "$#" -eq 0 ] && [ -s /System/Settings/browser/midori-start-pages ]; then
  set --
  while IFS= read -r start_url; do
    case "${start_url}" in
      ''|'#'*) continue ;;
    esac
    set -- "$@" "${start_url}"
  done < /System/Settings/browser/midori-start-pages
fi
set -- --profile "${HOME}/.midori" "$@"
exec ./midori "$@"
EOF
chmod 0755 "${MIDORI_PROGRAM}/Commands/midori"

cat > "${AUZIX_ROOT}/System/Settings/browser/midori-start-pages" <<'EOF'
https://auzietek.com
https://linux-users.auzietek.com/post/auzix-alpha-install-field-note?page=1&page_size=100&tag=linux&theme=linux-pro&lane=linux#article-start
EOF

ln -sfn "/Programs/Midori/${MIDORI_VERSION}" "${AUZIX_ROOT}/Programs/Midori/current"
ln -sfn /Programs/Midori/current/Commands/midori "${AUZIX_ROOT}/System/Compatibility/bin/midori"
ln -sfn /Programs/Midori/current/Commands/midori "${RUNTIME_USR}/bin/midori"

if [[ -f "${MIDORI_PROGRAM}/Resources/midori/browser/chrome/icons/default/default128.png" ]]; then
  cp -f "${MIDORI_PROGRAM}/Resources/midori/browser/chrome/icons/default/default128.png" \
    "${RUNTIME_USR}/share/pixmaps/midori.png"
fi

cat > "${RUNTIME_USR}/share/applications/auzix-midori.desktop" <<'EOF_DESKTOP'
[Desktop Entry]
Type=Application
Name=Midori
Comment=Browse the web with Midori
TryExec=midori
Exec=midori %u
Icon=midori
Categories=Network;WebBrowser;
Terminal=false
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
EOF_DESKTOP

cat > "${AUZIX_ROOT}/System/PackageDB/Midori-${MIDORI_VERSION}.auzix.json" <<EOF
{
  "name": "Midori",
  "version": "${MIDORI_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-optional-browser",
  "prefix": "/Programs/Midori/${MIDORI_VERSION}",
  "depends": [
    "Curl",
    "DBus",
    "Xorg"
  ],
  "paths": {
    "current": "/Programs/Midori/current"
  },
  "commands": [
    "/Programs/Midori/${MIDORI_VERSION}/Commands/midori",
    "/Programs/Midori/${MIDORI_VERSION}/Resources/midori/midori"
  ],
  "runtime_libraries": [
    "/Programs/Midori/${MIDORI_VERSION}/Libraries",
    "/Programs/Midori/${MIDORI_VERSION}/Resources/midori"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/midori",
    "/System/Compatibility/usr/bin/midori",
    "/System/Compatibility/usr/share/applications/auzix-midori.desktop",
    "/System/Compatibility/usr/share/pixmaps/midori.png",
    "/System/Settings/browser/midori-start-pages"
  ],
  "notes": "Optional heavyweight Midori browser package built from upstream v${MIDORI_VERSION} linux-x86_64 tarball. Kept out of the base live ISO by default."
}
EOF

log "Midori installed at ${MIDORI_PROGRAM}"
