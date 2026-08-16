#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
OS_SOURCE_CONTRACT="${ROOT_DIR}/packages/auzix-os.source.json"
AGENT="${AUZIX_ROOT}/System/Tools/auzix-live-agent"
SEQUENCE="${AUZIX_ROOT}/System/Boot/StartSequence"
FINALIZER="${AUZIX_ROOT}/System/Tools/finalize-installed-root"
INSTALL_PACKAGE="${AUZIX_ROOT}/System/Tools/auzix-install-package"
INSTALL_DISK="${AUZIX_ROOT}/System/Tools/auzix-install-disk"
INSTALL_PREFLIGHT="${AUZIX_ROOT}/System/Tools/auzix-existing-installer-preflight"
PATH_CONTRACT="${AUZIX_ROOT}/System/Settings/auzix-paths.sh"
ENVIRONMENT="${AUZIX_ROOT}/System/Settings/environment.sh"
START_E="${AUZIX_ROOT}/System/Tools/start-e"
START_E_SESSION="${AUZIX_ROOT}/System/Tools/start-enlightenment-session"
LIGHTDM_WRAPPER="${AUZIX_ROOT}/System/Tools/lightdm-session-wrapper"
LIGHTDM_SESSION="${AUZIX_ROOT}/System/Tools/lightdm-auzix-session"

fail() { printf '[auzix-live-agent] FAIL: %s\n' "$*" >&2; exit 1; }

if [[ -x "${ROOT_DIR}/scripts/validate-auzix-os-source-contract.sh" ]]; then
  "${ROOT_DIR}/scripts/validate-auzix-os-source-contract.sh" "${OS_SOURCE_CONTRACT}" "${AUZIX_ROOT}" >/dev/null ||
    fail "OS source contract validation failed"
fi

[[ -x "${AGENT}" ]] || fail "missing executable ${AGENT}"
[[ -x "${SEQUENCE}" ]] || fail "missing executable ${SEQUENCE}"
[[ -x "${FINALIZER}" ]] || fail "missing executable ${FINALIZER}"
[[ -x "${INSTALL_PACKAGE}" ]] || fail "missing executable ${INSTALL_PACKAGE}"
[[ -x "${INSTALL_DISK}" ]] || fail "missing executable ${INSTALL_DISK}"
[[ -x "${INSTALL_PREFLIGHT}" ]] || fail "missing executable ${INSTALL_PREFLIGHT}"
[[ -r "${PATH_CONTRACT}" ]] || fail "missing canonical bootstrap path contract ${PATH_CONTRACT}"
[[ -r "${ENVIRONMENT}" ]] || fail "missing interactive environment shim ${ENVIRONMENT}"
grep -Fq '. /System/Settings/auzix-paths.sh' "${ENVIRONMENT}" || fail "environment.sh does not source canonical AUZiX paths"
grep -Fq 'AUZIX_COMPAT_USR' "${PATH_CONTRACT}" || fail "path contract lacks AUZiX compatibility root definitions"
grep -Fq 'LD_LIBRARY_PATH=' "${PATH_CONTRACT}" || fail "path contract lacks canonical library path"
grep -Fq 'XDG_DATA_DIRS=' "${PATH_CONTRACT}" || fail "path contract lacks canonical XDG data path"
grep -Fq 'E_PREFIX=' "${PATH_CONTRACT}" || fail "path contract lacks Enlightenment prefix"
grep -Fq 'GCONV_PATH=' "${PATH_CONTRACT}" || fail "path contract lacks glibc conversion path"
for script in "${SEQUENCE}" "${START_E}" "${START_E_SESSION}" "${LIGHTDM_WRAPPER}" "${LIGHTDM_SESSION}"; do
  [[ -e "${script}" ]] || continue
  grep -Fq '/System/Settings/auzix-paths.sh' "${script}" || fail "${script#${AUZIX_ROOT}} does not source canonical AUZiX paths"
done
grep -Fq 'auzix-live-agent collect boot' "${SEQUENCE}" || fail "StartSequence does not collect a boot receipt"
grep -Fq 'opens no listener' "${AGENT}" || fail "agent safety contract missing"
grep -Fq 'https://example.com' "${AGENT}" || fail "agent lacks HTTPS validation probe"
grep -Fq 'command -v curl' "${AGENT}" || fail "agent does not prefer the packaged curl probe"
grep -Fq 'finalized-installed-root=' "${FINALIZER}" || fail "installer finalizer marker is missing"
grep -Fq '/Users/auzix/.midori' "${FINALIZER}" || fail "installer finalizer omits Midori state"
grep -Fq '/Programs/Sudo/host/Commands/sudo' "${FINALIZER}" || fail "installer finalizer omits sudo"
grep -Fq '/System/Compatibility/usr/lib/xorg/Xorg.wrap' "${FINALIZER}" || fail "installer finalizer omits Xorg wrapper"
grep -Fq '${target_root%/}/System/Tools/finalize-installed-root" "${target_root}"' "${INSTALL_PACKAGE}" || fail "package install handoff omits finalizer"
grep -Fq '/Work/InstallTarget/System/Tools/finalize-installed-root /Work/InstallTarget' "${INSTALL_DISK}" || fail "disk install handoff omits finalizer"
grep -Fq 'AUZIX_ALLOW_EXT2_FALLBACK' "${INSTALL_DISK}" || fail "disk install allows ext2 fallback without explicit guard"
grep -Fq 'RUN_INSTALL is not 1; preflight only' "${INSTALL_PREFLIGHT}" || fail "installer preflight is not safe by default"
grep -Fq 'fstab uses ext4 root' "${INSTALL_PREFLIGHT}" || fail "installer preflight lacks installed ext4 sanity gate"
printf '[auzix-live-agent] PASS: diagnostic agent is wired into the live boot path\n'
