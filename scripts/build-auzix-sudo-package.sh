#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
SUDO_VERSION="${AUZIX_SUDO_VERSION:-host}"
SUDO_PROGRAM="${AUZIX_ROOT}/Programs/Sudo/${SUDO_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"

log() {
  printf '[auzix-sudo] %s\n' "$*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

copy_runtime_deps() {
  local binary="$1"
  local dep
  ldd "${binary}" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' | sort -u |
  while IFS= read -r dep; do
    [[ -e "${dep}" ]] || continue
    case "$(basename "${dep}")" in
      ld-linux-x86-64.so.2|libc.so.6|libm.so.6|libpthread.so.0|libdl.so.2|librt.so.1)
        # RuntimeGlibc owns the core ABI, including the secure loader path.
        continue
        ;;
    esac
    case "${dep}" in
      /lib64/*)
        install -D -m 0755 "${dep}" "${RUNTIME_LIB64}/$(basename "${dep}")"
        ;;
      /lib/x86_64-linux-gnu/*|/usr/lib/x86_64-linux-gnu/*)
        install -D -m 0755 "${dep}" "${RUNTIME_LIB}/$(basename "${dep}")"
        ;;
      /usr/libexec/sudo/*)
        install -D -m 0755 "${dep}" "${AUZIX_ROOT}/System/Compatibility${dep}"
        ;;
      /usr/libexec/*)
        install -D -m 0755 "${dep}" "${AUZIX_ROOT}/System/Compatibility${dep}"
        ;;
      /usr/lib/*|/usr/share/*)
        install -D -m 0755 "${dep}" "${AUZIX_ROOT}/System/Compatibility${dep}"
        ;;
      *)
        install -D -m 0755 "${dep}" "${AUZIX_ROOT}${dep}"
        ;;
    esac
  done
}

copy_binary() {
  local source="$1"
  local target="$2"
  install -D -m 0755 "${source}" "${target}"
  copy_runtime_deps "${source}"
  # setuid programs cannot depend on LD_LIBRARY_PATH from a user session.
  patchelf --force-rpath --set-rpath \
    /System/Libraries/Runtime/glibc:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/usr/libexec/sudo \
    "${target}"
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

require_cmd sudo
require_cmd ldd
require_cmd install
require_cmd patchelf

VISUDO_PATH="$(command -v visudo || true)"
if [[ -z "${VISUDO_PATH}" && -x /usr/sbin/visudo ]]; then
  VISUDO_PATH=/usr/sbin/visudo
fi
if [[ -z "${VISUDO_PATH}" || ! -x "${VISUDO_PATH}" ]]; then
  printf 'Missing required command: visudo\n' >&2
  exit 1
fi

mkdir -p \
  "${SUDO_PROGRAM}/Commands" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/bin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/sbin" \
  "${AUZIX_ROOT}/System/Settings/sudoers.d" \
  "${AUZIX_ROOT}/System/PackageDB" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}"

chmod u+w \
  "${AUZIX_ROOT}/System/Settings/sudoers" \
  "${AUZIX_ROOT}/System/Settings/sudoers.d/README" 2>/dev/null || true

copy_binary "$(command -v sudo)" "${SUDO_PROGRAM}/Commands/sudo"
copy_binary "${VISUDO_PATH}" "${SUDO_PROGRAM}/Commands/visudo"
if command -v cvtsudoers >/dev/null 2>&1; then
  copy_binary "$(command -v cvtsudoers)" "${SUDO_PROGRAM}/Commands/cvtsudoers"
fi

if [[ -d /usr/libexec/sudo ]]; then
  rm -rf "${AUZIX_ROOT}/System/Compatibility/usr/libexec/sudo"
  mkdir -p "${AUZIX_ROOT}/System/Compatibility/usr/libexec"
  cp -a /usr/libexec/sudo "${AUZIX_ROOT}/System/Compatibility/usr/libexec/sudo"
  find "${AUZIX_ROOT}/System/Compatibility/usr/libexec/sudo" -type f -perm /111 |
  while IFS= read -r helper; do
    copy_runtime_deps "${helper}" || true
  done
fi

for pam_module in \
  /lib/x86_64-linux-gnu/security/pam_permit.so \
  /lib/x86_64-linux-gnu/security/pam_deny.so \
  /lib/x86_64-linux-gnu/security/pam_unix.so \
  /lib/x86_64-linux-gnu/security/pam_env.so; do
  [[ -e "${pam_module}" ]] || continue
  install -D -m 0755 "${pam_module}" "${AUZIX_ROOT}/System/Compatibility${pam_module}"
  copy_runtime_deps "${pam_module}" || true
done

ln -sfn "/Programs/Sudo/${SUDO_VERSION}/Commands/sudo" "${AUZIX_ROOT}/System/Compatibility/bin/sudo"
ln -sfn "/Programs/Sudo/${SUDO_VERSION}/Commands/sudo" "${AUZIX_ROOT}/System/Compatibility/usr/bin/sudo"
ln -sfn "/Programs/Sudo/${SUDO_VERSION}/Commands/visudo" "${AUZIX_ROOT}/System/Compatibility/usr/sbin/visudo"
if [[ -x "${SUDO_PROGRAM}/Commands/cvtsudoers" ]]; then
  ln -sfn "/Programs/Sudo/${SUDO_VERSION}/Commands/cvtsudoers" "${AUZIX_ROOT}/System/Compatibility/usr/bin/cvtsudoers"
fi

chown root:root "${SUDO_PROGRAM}/Commands/sudo" 2>/dev/null || true
chmod 4755 "${SUDO_PROGRAM}/Commands/sudo"

cat > "${AUZIX_ROOT}/System/Settings/sudo.conf" <<'EOF'
Plugin sudoers_policy sudoers.so
Plugin sudoers_io sudoers.so
EOF

cat > "${AUZIX_ROOT}/System/Settings/sudoers" <<'EOF'
Defaults env_reset
Defaults secure_path="/System/Compatibility/sbin:/System/Compatibility/bin:/System/Compatibility/usr/sbin:/System/Compatibility/usr/bin:/Programs/BusyBox/1.36.1/Commands"
Defaults mail_badpass

root ALL=(ALL:ALL) ALL
%sudo ALL=(ALL:ALL) NOPASSWD: ALL
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
@includedir /System/Settings/sudoers.d
EOF
chmod 0440 "${AUZIX_ROOT}/System/Settings/sudoers"

# The alpha workstation account must retain its recovery/admin lane even when
# an already-running graphical session predates supplementary-group changes.
cat > "${AUZIX_ROOT}/System/Settings/sudoers.d/auzix" <<'EOF'
auzix ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 0440 "${AUZIX_ROOT}/System/Settings/sudoers.d/auzix"

cat > "${AUZIX_ROOT}/System/Settings/sudoers.d/README.md" <<'EOF'
Drop sudoers fragments here. Files are included by /System/Settings/sudoers.
EOF
chmod 0440 "${AUZIX_ROOT}/System/Settings/sudoers.d/README.md"

mkdir -p "${AUZIX_ROOT}/System/Settings/pam.d"
cat > "${AUZIX_ROOT}/System/Settings/pam.d/sudo" <<'EOF'
#%PAM-1.0
auth sufficient /System/Compatibility/lib/x86_64-linux-gnu/security/pam_permit.so
account sufficient /System/Compatibility/lib/x86_64-linux-gnu/security/pam_permit.so
session optional /System/Compatibility/lib/x86_64-linux-gnu/security/pam_permit.so
EOF
cp -f "${AUZIX_ROOT}/System/Settings/pam.d/sudo" "${AUZIX_ROOT}/System/Settings/pam.d/sudo-i"
chmod 0644 "${AUZIX_ROOT}/System/Settings/pam.d/sudo" "${AUZIX_ROOT}/System/Settings/pam.d/sudo-i"

cat > "${AUZIX_ROOT}/System/PackageDB/Sudo-${SUDO_VERSION}.auzix.json" <<EOF
{
  "name": "Sudo",
  "version": "${SUDO_VERSION}",
  "kind": "program",
  "migration_stage": "stage-1-compat-install",
  "prefix": "/Programs/Sudo/${SUDO_VERSION}",
  "commands": [
    "/Programs/Sudo/${SUDO_VERSION}/Commands/sudo",
    "/Programs/Sudo/${SUDO_VERSION}/Commands/visudo"
  ],
  "settings": [
    "/System/Settings/sudo.conf",
    "/System/Settings/sudoers",
    "/System/Settings/sudoers.d"
  ],
  "compatibility_exports": [
    "/System/Compatibility/bin/sudo",
    "/System/Compatibility/usr/bin/sudo",
    "/System/Compatibility/usr/sbin/visudo"
  ],
  "notes": "Live-session sudo is passwordless for auzix via sudo/wheel groups."
}
EOF

log "Sudo runtime installed at ${SUDO_PROGRAM}"
