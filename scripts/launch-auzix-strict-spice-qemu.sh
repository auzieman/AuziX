#!/usr/bin/env bash
set -euo pipefail

# Launch the latest strict AUZiX live ISO under QEMU with:
# - serial console on stdio for rescue/boot proof
# - SPICE on port 5930 for graphical inspection
# - user networking with host port 2222 forwarded to guest SSH if enabled
#
# Typical remote use from a workstation:
#   ssh -L 5930:127.0.0.1:5930 lab-ai-worker
#   remote-viewer spice://127.0.0.1:5930

iso="${1:-}"
if [[ -z "${iso}" ]]; then
  receipt="/var/lib/auzix-build/receipts/live-build-current.run"
  if [[ -s "${receipt}" ]]; then
    run="$(cat "${receipt}")"
    iso="/var/lib/auzix-build/runs/${run}/src/artifacts/auzix/auzix-strict-tty-spice-r4.iso"
  else
    iso="$(
      find /var/lib/auzix-build/runs -path '*/src/artifacts/auzix/auzix-strict-tty-spice-r4.iso' \
        -type f -printf '%T@ %p\n' 2>/dev/null |
        sort -nr |
        awk 'NR == 1 {print $2}'
    )"
  fi
fi

test -n "${iso}" && test -f "${iso}" || {
  printf 'ISO not found. Pass the ISO path explicitly, e.g.:\n' >&2
  printf '  %s /var/lib/auzix-build/runs/<run>/src/artifacts/auzix/auzix-strict-tty-spice-r4.iso\n' "$0" >&2
  exit 1
}

spice_addr="${AUZIX_SPICE_ADDR:-127.0.0.1}"
spice_port="${AUZIX_SPICE_PORT:-5930}"
serial_log="${AUZIX_QEMU_SERIAL_LOG:-/tmp/auzix-strict-spice-serial.log}"

printf 'AUZiX ISO: %s\n' "${iso}" >&2
printf 'SPICE: spice://%s:%s\n' "${spice_addr}" "${spice_port}" >&2
printf 'If remote, tunnel with: ssh -L %s:127.0.0.1:%s lab-ai-worker\n' "${spice_port}" "${spice_port}" >&2
printf 'Then connect with: remote-viewer spice://127.0.0.1:%s\n' "${spice_port}" >&2

serial_args=(-serial mon:stdio)
if [[ "${AUZIX_QEMU_DETACH:-0}" == "1" ]]; then
  serial_args=(-serial "file:${serial_log}" -daemonize)
  printf 'Detached mode: serial log -> %s\n' "${serial_log}" >&2
fi

exec qemu-system-x86_64 \
  -machine q35,accel=kvm \
  -cpu host \
  -m "${AUZIX_QEMU_MEM:-2048}" \
  -smp "${AUZIX_QEMU_SMP:-2}" \
  -cdrom "${iso}" \
  -boot d \
  "${serial_args[@]}" \
  -no-reboot \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  -device e1000,netdev=n0 \
  -device qxl-vga \
  -spice "addr=${spice_addr},port=${spice_port},disable-ticketing=on" \
  -audiodev spice,id=spiceaudio \
  -device ich9-intel-hda \
  -device hda-output,audiodev=spiceaudio \
  -display none
