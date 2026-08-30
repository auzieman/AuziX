#!/usr/bin/env bash
set -euo pipefail

# Fast runtime boot gate for AUZiX live ISOs.
#
# This is intentionally separate from validate-auzix-boot-iso.sh. The static
# validator checks ISO structure; this script boots the artifact and asks the
# practical question: did init reach network/services quickly enough to promote
# the ISO to ESXi/PVE testing?

ISO_PATH="${1:-}"
TIMEOUT_SECONDS="${AUZIX_QEMU_SMOKE_TIMEOUT:-120}"
MEMORY_MB="${AUZIX_QEMU_SMOKE_MEMORY_MB:-1024}"
CPUS="${AUZIX_QEMU_SMOKE_CPUS:-2}"
OUT_DIR="${AUZIX_QEMU_SMOKE_OUT_DIR:-/var/lib/auzix-build/qemu-smoke}"
NAME="${AUZIX_QEMU_SMOKE_NAME:-$(date -u +%Y%m%dT%H%M%SZ)}"
REQUIRE_SSH="${AUZIX_QEMU_REQUIRE_SSH:-0}"
REQUIRE_DHCP="${AUZIX_QEMU_REQUIRE_DHCP:-1}"
REQUIRE_DISPLAY_HANDOFF="${AUZIX_QEMU_REQUIRE_DISPLAY_HANDOFF:-0}"
REQUIRE_DISPLAY_ALIVE="${AUZIX_QEMU_REQUIRE_DISPLAY_ALIVE:-0}"
REQUIRE_MIDORI="${AUZIX_QEMU_REQUIRE_MIDORI:-0}"
REQUIRE_MIDORI_CA_CLEAN="${AUZIX_QEMU_REQUIRE_MIDORI_CA_CLEAN:-0}"
DISPLAY_MODE="${AUZIX_QEMU_DISPLAY:-none}"
VIDEO_DEVICE="${AUZIX_QEMU_VIDEO_DEVICE:-virtio-vga}"
VNC_DISPLAY="${AUZIX_QEMU_VNC_DISPLAY:-7}"
SPICE_PORT="${AUZIX_QEMU_SPICE_PORT:-5930}"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  [[ -n "${SERIAL_LOG:-}" && -f "${SERIAL_LOG}" ]] && {
    printf '\n--- serial tail: %s ---\n' "${SERIAL_LOG}" >&2
    tail -120 "${SERIAL_LOG}" >&2 || true
  }
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "required command missing: $1"
}

usage() {
  cat <<'EOF'
Usage:
  scripts/smoke-auzix-iso-qemu.sh /path/to/auzix.iso

Environment:
  AUZIX_QEMU_SMOKE_TIMEOUT=120       wall-clock seconds before QEMU is stopped
  AUZIX_QEMU_SMOKE_OUT_DIR=...       serial/error log output directory
  AUZIX_QEMU_SMOKE_NAME=...          log basename
  AUZIX_QEMU_REQUIRE_SSH=0           optionally require "ssh tcp/22 listening"
  AUZIX_QEMU_REQUIRE_DHCP=1          require DHCP IPv4 marker
  AUZIX_QEMU_REQUIRE_DISPLAY_HANDOFF=0 require display handoff marker
  AUZIX_QEMU_REQUIRE_DISPLAY_ALIVE=0 require post-handoff X/E process evidence
  AUZIX_QEMU_REQUIRE_MIDORI=0        require Midori smoke process evidence
  AUZIX_QEMU_REQUIRE_MIDORI_CA_CLEAN=0 require CA bundle + HTTPS probe without CA errors
  AUZIX_QEMU_DISPLAY=none            none|vnc|spice|spice-app|gtk|sdl
  AUZIX_QEMU_VIDEO_DEVICE=virtio-vga virtio-vga|qxl-vga|vmware-svga|VGA
  AUZIX_QEMU_VNC_DISPLAY=7           VNC display number, port 5900+n
  AUZIX_QEMU_SPICE_PORT=5930         SPICE TCP port when DISPLAY=spice

The ISO should already include console=ttyS0,115200 so the gate can read the
boot through the serial log without depending on a graphical console.
EOF
}

if [[ -z "${ISO_PATH}" || "${ISO_PATH}" == "-h" || "${ISO_PATH}" == "--help" ]]; then
  usage
  [[ -n "${ISO_PATH}" ]] && exit 0 || exit 2
fi

need qemu-system-x86_64
need timeout
test -f "${ISO_PATH}" || fail "ISO not found: ${ISO_PATH}"

mkdir -p "${OUT_DIR}"
SERIAL_LOG="${OUT_DIR}/${NAME}.serial.log"
QEMU_ERR="${OUT_DIR}/${NAME}.qemu.err"
rm -f "${SERIAL_LOG}" "${QEMU_ERR}"

ACCEL_ARGS=(-machine q35,accel=kvm -cpu host)
if [[ ! -e /dev/kvm ]]; then
  ACCEL_ARGS=(-machine q35,accel=tcg -cpu max)
fi

printf '[auzix-qemu-smoke] iso=%s\n' "${ISO_PATH}"
printf '[auzix-qemu-smoke] timeout=%ss serial=%s\n' "${TIMEOUT_SECONDS}" "${SERIAL_LOG}"

QEMU_ARGS=(
  "${ACCEL_ARGS[@]}" \
  -m "${MEMORY_MB}" \
  -smp "${CPUS}" \
  -cdrom "${ISO_PATH}" \
  -boot d \
  -serial "file:${SERIAL_LOG}" \
  -no-reboot \
  -netdev user,id=n0 \
  -device e1000,netdev=n0
)

case "${DISPLAY_MODE}" in
  none)
    QEMU_ARGS+=(-display none)
    ;;
  vnc)
    QEMU_ARGS+=(-device "${VIDEO_DEVICE}" -display "vnc=0.0.0.0:${VNC_DISPLAY}")
    printf '[auzix-qemu-smoke] vnc=0.0.0.0:%s tcp=%s\n' "${VNC_DISPLAY}" "$((5900 + VNC_DISPLAY))"
    ;;
  spice)
    QEMU_ARGS+=(
      -device "${VIDEO_DEVICE}"
      -spice "addr=0.0.0.0,port=${SPICE_PORT},disable-ticketing=on"
      -audiodev spice,id=spiceaudio
      -display none
    )
    printf '[auzix-qemu-smoke] spice=0.0.0.0:%s ticketing=off\n' "${SPICE_PORT}"
    ;;
  spice-app)
    QEMU_ARGS+=(-device "${VIDEO_DEVICE}" -display spice-app)
    ;;
  gtk|sdl)
    QEMU_ARGS+=(-device "${VIDEO_DEVICE}" -display "${DISPLAY_MODE}")
    ;;
  *)
    fail "unknown AUZIX_QEMU_DISPLAY=${DISPLAY_MODE}"
    ;;
esac

timeout "${TIMEOUT_SECONDS}s" qemu-system-x86_64 "${QEMU_ARGS[@]}" \
  > /dev/null 2>"${QEMU_ERR}" || true

test -s "${SERIAL_LOG}" || fail "serial log is empty"

grep -aF '[StartSequence] stage: mounting runtime filesystems' "${SERIAL_LOG}" >/dev/null ||
  fail "StartSequence did not begin"

if [[ "${REQUIRE_DHCP}" == "1" ]]; then
  grep -aE '\[StartSequence\] network: .*ipv4=[0-9]+\.' "${SERIAL_LOG}" >/dev/null ||
    fail "DHCP/IPv4 marker missing"
fi

grep -aF '[StartSequence] stage: starting declared services' "${SERIAL_LOG}" >/dev/null ||
  fail "service stage marker missing"

if [[ "${REQUIRE_SSH}" == "1" ]]; then
  grep -aF '[StartSequence] services: ssh tcp/22 listening' "${SERIAL_LOG}" >/dev/null ||
    fail "SSH did not reach tcp/22 listening"
fi

if [[ "${REQUIRE_DISPLAY_HANDOFF}" == "1" ]]; then
  grep -aF '[StartSequence] stage: starting display' "${SERIAL_LOG}" >/dev/null ||
    fail "display handoff marker missing"
fi

if [[ "${REQUIRE_DISPLAY_ALIVE}" == "1" ]]; then
  grep -aF '[StartSequence] display: X/E process observed' "${SERIAL_LOG}" >/dev/null ||
    fail "display process evidence missing"
fi

if [[ "${REQUIRE_MIDORI}" == "1" ]]; then
  grep -aF '[StartSequence] display: Midori process observed' "${SERIAL_LOG}" >/dev/null ||
    fail "Midori process evidence missing"
fi

if [[ "${REQUIRE_MIDORI_CA_CLEAN}" == "1" ]]; then
  grep -aF '[StartSequence] midori-check: ca_bundle=ready' "${SERIAL_LOG}" >/dev/null ||
    fail "Midori CA bundle is not ready"
  grep -aF '[StartSequence] midori-check: https_probe:' "${SERIAL_LOG}" >/dev/null ||
    fail "Midori HTTPS probe did not run"
  grep -aF '[StartSequence] midori-check: ok' "${SERIAL_LOG}" >/dev/null ||
    fail "Midori HTTPS probe did not succeed"
fi

if grep -aEi 'kernel panic|not syncing|error while loading shared libraries|symbol lookup error|stack smashing detected|segmentation fault|GLIBC_[0-9].*not found' "${SERIAL_LOG}" >/dev/null; then
  fail "fatal runtime marker found"
fi

if grep -aEi 'Problem with the SSL CA cert|certificate verify failed|unknown issuer|SEC_ERROR_UNKNOWN_ISSUER|unable to get local issuer certificate' "${SERIAL_LOG}" >/dev/null; then
  fail "CA/trust failure marker found"
fi

printf '[auzix-qemu-smoke] markers:\n'
grep -aE '\[StartSequence\] (stage:|network:|services:|display:|display-log:)|Auzix rescue shell' "${SERIAL_LOG}" | tail -120 || true
printf 'PASS: qemu ISO boot smoke: %s\n' "${ISO_PATH}"
