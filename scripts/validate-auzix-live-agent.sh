#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
AGENT="${AUZIX_ROOT}/System/Tools/auzix-live-agent"
SEQUENCE="${AUZIX_ROOT}/System/Boot/StartSequence"
FINALIZER="${AUZIX_ROOT}/System/Tools/finalize-installed-root"
INSTALL_PACKAGE="${AUZIX_ROOT}/System/Tools/auzix-install-package"
INSTALL_DISK="${AUZIX_ROOT}/System/Tools/auzix-install-disk"

fail() { printf '[auzix-live-agent] FAIL: %s\n' "$*" >&2; exit 1; }

[[ -x "${AGENT}" ]] || fail "missing executable ${AGENT}"
[[ -x "${SEQUENCE}" ]] || fail "missing executable ${SEQUENCE}"
[[ -x "${FINALIZER}" ]] || fail "missing executable ${FINALIZER}"
[[ -x "${INSTALL_PACKAGE}" ]] || fail "missing executable ${INSTALL_PACKAGE}"
[[ -x "${INSTALL_DISK}" ]] || fail "missing executable ${INSTALL_DISK}"
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
printf '[auzix-live-agent] PASS: diagnostic agent is wired into the live boot path\n'
