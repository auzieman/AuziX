#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${ROOT_DIR}"

run_step() {
  printf '[auzix-build-all] %s\n' "$*" >&2
  "$@"
}

run_step make auzix-strict-root
run_step make auzix-strict-probe
run_step make auzix-strict-dynprobe
run_step make auzix-strict-busybox
run_step make auzix-strict-access
run_step make auzix-strict-iputils
run_step make auzix-strict-package-tools
run_step make auzix-strict-sudo
run_step make auzix-strict-dbus
run_step make auzix-strict-udev
run_step make auzix-strict-acpid
run_step make auzix-strict-pulseaudio
run_step make auzix-strict-alsa
run_step make auzix-strict-strace
run_step make auzix-strict-curl
run_step make auzix-strict-host-xorg
run_step make auzix-strict-host-e
run_step make auzix-strict-host-terminology
run_step make auzix-strict-host-xterm
run_step make auzix-strict-netsurf
run_step make auzix-strict-lightdm
run_step make auzix-strict-display-templates
run_step make auzix-strict-user-defaults
run_step make auzix-strict-live-tools
run_step make auzix-strict-kernel-modules
run_step make auzix-strict-package-repo
run_step make auzix-strict-audit
run_step make auzix-strict-iso
