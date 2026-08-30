#!/usr/bin/env bash
set -euo pipefail

AUZIX_ROOT="${1:-out/auzix-strict/AuzixRoot}"
AUZIX_LOADER="/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2"
AUZIX_RUNPATH="/System/Libraries:/System/Libraries/Runtime/glibc:\$ORIGIN/../Libraries:\$ORIGIN:\$ORIGIN/..:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64"

log() {
  printf '[auzix-elf-normalize] %s\n' "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

require_cmd find
require_cmd patchelf
require_cmd readelf

[[ -d "${AUZIX_ROOT}/Programs" ]] || {
  printf 'AUZiX root missing Programs directory: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
}
[[ -x "${AUZIX_ROOT}${AUZIX_LOADER}" ]] || {
  printf 'AUZiX loader missing: %s%s\n' "${AUZIX_ROOT}" "${AUZIX_LOADER}" >&2
  exit 1
}

patched=0
skipped=0
failed=0

scan_roots=(
  "${AUZIX_ROOT}/Programs"
  "${AUZIX_ROOT}/System/Tools"
  # Compatibility payloads are not top-level legacy aliases; they are AUZiX's
  # native compatibility namespace.  Xorg stages its real server here, and if
  # we skip this tree the wrapper reaches an ELF that still asks for /lib64.
  "${AUZIX_ROOT}/System/Compatibility"
)

while IFS= read -r elf; do
  [[ -f "${elf}" ]] || continue
  if ! readelf -h "${elf}" >/dev/null 2>&1; then
    continue
  fi

  # Do not mutate glibc itself.  The dynamic loader and core runtime libraries
  # are the substrate; patchelfing them corrupts the process that loads every
  # other dynamic command.  Everything else should point at this substrate.
  case "${elf#${AUZIX_ROOT}}" in
    /System/Libraries/Runtime/glibc/*|\
    /System/Compatibility/lib64/ld-linux-x86-64.so.2|\
    /System/Compatibility/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2|\
    /System/Compatibility/lib/x86_64-linux-gnu/libc.so.6|\
    */Libraries/ld-linux-x86-64.so.2|\
    */Libraries/libc.so.6)
      skipped=$((skipped + 1))
      continue
      ;;
  esac

  interpreter="$(
    readelf -l "${elf}" 2>/dev/null |
      sed -n 's#.*Requesting program interpreter: \(.*\)]#\1#p' |
      head -1
  )"
  has_dynamic=0
  if readelf -d "${elf}" 2>/dev/null | grep -q 'Dynamic section'; then
    has_dynamic=1
  fi
  if [[ -z "${interpreter}" && "${has_dynamic}" -eq 0 ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  if [[ -n "${interpreter}" ]]; then
    if ! patchelf --set-interpreter "${AUZIX_LOADER}" "${elf}" 2>/tmp/auzix-patchelf.err; then
      printf '[auzix-elf-normalize] failed interpreter patch: %s\n' "${elf}" >&2
      cat /tmp/auzix-patchelf.err >&2 || true
      failed=$((failed + 1))
      continue
    fi
  fi

  if [[ "${has_dynamic}" -eq 1 ]]; then
    if ! patchelf --set-rpath "${AUZIX_RUNPATH}" "${elf}" 2>/tmp/auzix-patchelf.err; then
      printf '[auzix-elf-normalize] failed rpath patch: %s\n' "${elf}" >&2
      cat /tmp/auzix-patchelf.err >&2 || true
      failed=$((failed + 1))
      continue
    fi
  fi

  patched=$((patched + 1))

done < <(find "${scan_roots[@]}" -type f -perm /111 2>/dev/null | sort)

rm -f /tmp/auzix-patchelf.err 2>/dev/null || true

log "patched=${patched} skipped=${skipped} failed=${failed}"
[[ "${failed}" -eq 0 ]]
