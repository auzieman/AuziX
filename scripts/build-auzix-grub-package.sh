#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
GRUB_INSTALL="${GRUB_INSTALL:-/usr/sbin/grub-install}"
GRUB_MKIMAGE="${GRUB_MKIMAGE:-/usr/bin/grub-mkimage}"
GRUB_PROBE="${GRUB_PROBE:-/usr/sbin/grub-probe}"
GRUB_BIOS_SETUP="${GRUB_BIOS_SETUP:-/usr/lib/grub/i386-pc/grub-bios-setup}"
VERSION="${AUZIX_GRUB_VERSION:-$("${GRUB_INSTALL}" --version | awk '{print $NF}')}"
PROGRAM_ROOT="${AUZIX_ROOT}/Programs/GRUB/${VERSION}"
COMPAT="${AUZIX_ROOT}/System/Compatibility"
RECEIPT="${AUZIX_ROOT}/System/PackageDB/GRUB-${VERSION}.auzix.json"

log() {
  printf '[auzix-grub] %s\n' "$*" >&2
}

copy_runtime_deps() {
  local binary="$1"
  local dep

  ldd "${binary}" 2>/dev/null |
    awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' |
    sort -u |
    while IFS= read -r dep; do
      [[ -e "${dep}" ]] || continue
      case "$(basename "${dep}")" in
        ld-linux-x86-64.so.2|libc.so.6|libm.so.6|libpthread.so.0|libdl.so.2|librt.so.1)
          # The target's runtime package owns the core ABI.
          continue
          ;;
      esac
      install -D -m 0755 "${dep}" "${PROGRAM_ROOT}/Libraries/$(basename "${dep}")"
    done
}

for source_path in "${GRUB_INSTALL}" "${GRUB_MKIMAGE}" "${GRUB_PROBE}" "${GRUB_BIOS_SETUP}"; do
  [[ -x "${source_path}" ]] || {
    printf 'Required GRUB command not found: %s\n' "${source_path}" >&2
    exit 1
  }
done
for command_name in install ldd jq; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "${command_name}" >&2
    exit 1
  }
done

rm -rf "${PROGRAM_ROOT}"
mkdir -p \
  "${PROGRAM_ROOT}/Commands" \
  "${PROGRAM_ROOT}/Libraries" \
  "${PROGRAM_ROOT}/Resources/i386-pc" \
  "${COMPAT}/usr/bin" \
  "${COMPAT}/usr/sbin" \
  "${COMPAT}/usr/lib/grub" \
  "${AUZIX_ROOT}/System/PackageDB"

for command_spec in \
  "grub-install:${GRUB_INSTALL}" \
  "grub-mkimage:${GRUB_MKIMAGE}" \
  "grub-probe:${GRUB_PROBE}" \
  "grub-bios-setup:${GRUB_BIOS_SETUP}"
do
  command_name="${command_spec%%:*}"
  source_path="${command_spec#*:}"
  install -m 0755 "${source_path}" "${PROGRAM_ROOT}/Commands/${command_name}.real"
  cat >"${PROGRAM_ROOT}/Commands/${command_name}" <<EOF_WRAPPER
#!/System/Compatibility/bin/sh
export LD_LIBRARY_PATH=/Programs/GRUB/${VERSION}/Libraries:/System/Libraries/Runtime/glibc\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}
exec /Programs/GRUB/${VERSION}/Commands/${command_name}.real "\$@"
EOF_WRAPPER
  chmod 0755 "${PROGRAM_ROOT}/Commands/${command_name}"
  copy_runtime_deps "${source_path}"
done

cp -a /usr/lib/grub/i386-pc/. "${PROGRAM_ROOT}/Resources/i386-pc/"
ln -sfn "/Programs/GRUB/${VERSION}" "${AUZIX_ROOT}/Programs/GRUB/current"
ln -sfn /Programs/GRUB/current/Commands/grub-install "${COMPAT}/usr/sbin/grub-install"
ln -sfn /Programs/GRUB/current/Commands/grub-probe "${COMPAT}/usr/sbin/grub-probe"
ln -sfn /Programs/GRUB/current/Commands/grub-mkimage "${COMPAT}/usr/bin/grub-mkimage"
ln -sfn /Programs/GRUB/current/Commands/grub-bios-setup "${COMPAT}/usr/sbin/grub-bios-setup"
ln -sfn /Programs/GRUB/current/Resources/i386-pc "${COMPAT}/usr/lib/grub/i386-pc"

cat >"${RECEIPT}" <<EOF
{
  "name": "GRUB",
  "version": "${VERSION}",
  "kind": "system",
  "migration_stage": "stage-1-installer",
  "prefix": "/Programs/GRUB/${VERSION}",
  "depends": [
    "BusyBox"
  ],
  "commands": [
    "/Programs/GRUB/${VERSION}/Commands/grub-install",
    "/Programs/GRUB/${VERSION}/Commands/grub-mkimage",
    "/Programs/GRUB/${VERSION}/Commands/grub-probe",
    "/Programs/GRUB/${VERSION}/Commands/grub-bios-setup"
  ],
  "compatibility_exports": [
    "/System/Compatibility/usr/sbin/grub-install",
    "/System/Compatibility/usr/sbin/grub-probe",
    "/System/Compatibility/usr/sbin/grub-bios-setup",
    "/System/Compatibility/usr/bin/grub-mkimage",
    "/System/Compatibility/usr/lib/grub/i386-pc"
  ],
  "notes": "BIOS GRUB installer and i386-pc modules used by auzix-install-disk."
}
EOF

log "GRUB ${VERSION} staged under ${PROGRAM_ROOT}"
