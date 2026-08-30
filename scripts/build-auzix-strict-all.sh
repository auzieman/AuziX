#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIVE_CURRENT_ONLY="${AUZIX_LIVE_CURRENT_ONLY:-0}"
ROOT_ONLY="${AUZIX_STRICT_ROOT_ONLY:-0}"

cd "${ROOT_DIR}"

if [[ "$(id -u)" != "0" && -z "${FAKEROOTKEY:-}" && "${AUZIX_ALLOW_UNPRIVILEGED_BUILD:-0}" != "1" ]]; then
  cat >&2 <<'EOF'
[auzix-build-all] refusing unprivileged strict build
[auzix-build-all] Package make/install/chown/chmod logic must be allowed to set
[auzix-build-all] ownership, setuid bits, sticky dirs, and package lifecycle state.
[auzix-build-all] Run this in the builder container/root-capable lab-build path,
[auzix-build-all] or under one fakeroot session that covers both staging and tar.
[auzix-build-all] Set AUZIX_ALLOW_UNPRIVILEGED_BUILD=1 only for throwaway dev roots.
EOF
  exit 1
fi

run_step() {
  printf '[auzix-build-all] %s\n' "$*" >&2
  "$@"
}

reset_owned_build_root() {
  local target="${ROOT_DIR}/out/auzix-strict/AuzixRoot"
  case "${target}" in
    "${ROOT_DIR}/out/auzix-strict/AuzixRoot") ;;
    *)
      printf '[auzix-build-all] refusing unsafe build-root reset: %s\n' "${target}" >&2
      exit 1
      ;;
  esac
  if [[ -e "${target}" || -L "${target}" ]]; then
    printf '[auzix-build-all] resetting owned build root: %s\n' "${target}" >&2
    rm -rf "${target}"
  fi
}

# STRICT LIVE BUILD CONTRACT:
# This order is intentional.  First create a clean AUZiX root, then install
# package payloads/receipts with their ownership and mode bits intact, then add
# live boot/display tools, then normalize/audit, then assemble the ISO.  Do not
# replace this with a filesystem clone from a test container: that skips package
# lifecycle state and has repeatedly produced init/lib/permission regressions.
reset_owned_build_root
run_step make auzix-strict-root
run_step make auzix-strict-probe
run_step make auzix-strict-dynprobe
run_step make auzix-strict-busybox
run_step env AUZIX_INCLUDE_OPENSSH="${AUZIX_INCLUDE_OPENSSH:-0}" make auzix-strict-access
run_step make auzix-strict-service-runtime
run_step make auzix-strict-iputils
run_step make auzix-strict-package-tools
run_step make auzix-strict-installer
if [[ "${AUZIX_SKIP_EFL_INSTALLER:-0}" == "1" ]]; then
  printf '[auzix-build-all] skipping EFL installer/package-manager because AUZIX_SKIP_EFL_INSTALLER=1\n' >&2
else
  run_step make auzix-strict-installer-efl
  run_step make auzix-strict-package-manager-efl
fi
if [[ "${AUZIX_SKIP_INSTALLER_TESTS:-0}" == "1" ]]; then
  printf '[auzix-build-all] skipping installer tests because AUZIX_SKIP_INSTALLER_TESTS=1\n' >&2
else
  run_step make auzix-strict-installer-test
fi
run_step ./scripts/build-auzix-command-suite-package.sh \
  out/auzix-strict/AuzixRoot packages/e2fsprogs.command-suite.json
run_step ./scripts/build-auzix-command-suite-package.sh \
  out/auzix-strict/AuzixRoot packages/parted.command-suite.json
run_step make auzix-strict-grub
run_step make auzix-strict-sudo
run_step make auzix-strict-dbus
run_step make auzix-strict-udev
run_step make auzix-strict-acpid
run_step make auzix-strict-pulseaudio
run_step make auzix-strict-alsa
run_step make auzix-strict-strace
run_step make auzix-strict-ca-certificates
run_step make auzix-strict-curl
run_step make auzix-strict-host-xorg
run_step make auzix-strict-host-e
run_step make auzix-strict-host-terminology
run_step make auzix-strict-host-xterm
run_step make auzix-strict-midori
run_step make auzix-strict-lightdm
run_step make auzix-strict-display-templates
run_step make auzix-strict-e-assets
run_step make auzix-strict-desktop-assets-package
run_step make auzix-strict-desktop-integration
if [[ "${LIVE_CURRENT_ONLY}" == "1" ]]; then
  printf '[auzix-build-all] current-live mode: skipping Flatpak runtime support/adapters until the live image carries proven Flatpak payloads and session services\n' >&2
else
  run_step make auzix-strict-flatpak-runtime-support
  run_step make auzix-strict-flatpak-adapters
fi
run_step make auzix-strict-user-defaults
run_step make auzix-strict-live-tools
if [[ "${AUZIX_SKIP_LIVE_AGENT_VALIDATION:-0}" == "1" ]]; then
  printf '[auzix-build-all] skipping live agent validation because AUZIX_SKIP_LIVE_AGENT_VALIDATION=1\n' >&2
else
  run_step ./scripts/validate-auzix-live-agent.sh
fi
if [[ "${AUZIX_SKIP_INSTALLER_TESTS:-0}" == "1" ]]; then
  printf '[auzix-build-all] skipping live installer demo test because AUZIX_SKIP_INSTALLER_TESTS=1\n' >&2
else
  run_step make auzix-strict-live-installer-demo-test
fi
run_step make auzix-strict-kernel-modules
if [[ "${AUZIX_SKIP_ELF_NORMALIZE:-0}" == "1" ]]; then
  printf '[auzix-build-all] skipping ELF interpreter normalization because AUZIX_SKIP_ELF_NORMALIZE=1\n' >&2
else
  run_step ./scripts/normalize-auzix-elf-runtime.sh out/auzix-strict/AuzixRoot
fi

if [[ "${ROOT_ONLY}" == "1" ]]; then
  printf '[auzix-build-all] root-only mode: stopping after the same validated live root sequence; caller owns media writer stage\n' >&2
  exit 0
fi

run_step make auzix-strict-package-repo
run_step env AUZIX_LEGACY_POLICY="${AUZIX_LEGACY_POLICY:-strict}" make auzix-strict-audit
run_step make auzix-strict-iso
