#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/}"
if [[ "${ROOT}" != "/" ]]; then
  ROOT="${ROOT%/}"
fi
CHROOT_BB=""
if [[ "${ROOT}" != "/" ]]; then
  for candidate in \
    "${ROOT}/Programs/BusyBox/current/Commands/busybox" \
    "${ROOT}/Programs/BusyBox/1.36.1/Commands/busybox"; do
    if [[ -x "${candidate}" || -L "${candidate}" ]]; then
      CHROOT_BB="${candidate#${ROOT}}"
      break
    fi
  done
fi

pp() {
  local path="$1"
  if [[ "${ROOT}" == "/" ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s%s\n' "${ROOT}" "${path}"
  fi
}

exists() {
  if [[ -n "${CHROOT_BB}" ]]; then
    chroot "${ROOT}" "${CHROOT_BB}" test -e "$1" 2>/dev/null ||
      chroot "${ROOT}" "${CHROOT_BB}" test -L "$1" 2>/dev/null
  else
    [[ -e "$(pp "$1")" || -L "$(pp "$1")" ]]
  fi
}

is_exec() {
  if [[ -n "${CHROOT_BB}" ]]; then
    chroot "${ROOT}" "${CHROOT_BB}" test -x "$1" 2>/dev/null
  else
    [[ -x "$(pp "$1")" ]]
  fi
}

section() {
  printf '\n== %s ==\n' "$*"
}

desktop_dirs=(
  /System/Compatibility/usr/share/applications
  /Users/auzix/.local/share/applications
)

section "AUZiX desktop launcher probe"
printf 'root=%s\n' "${ROOT}"
printf 'chroot_busybox=%s\n' "${CHROOT_BB:-none}"
printf 'time=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

section "core paths"
for path in \
  /Programs/BusyBox/current/Commands/busybox \
  /System/Compatibility/bin/sh \
  /System/Compatibility/bin/ls \
  /System/Settings/xdg/menus/e-applications.menu \
  /etc/xdg/menus/e-applications.menu \
  /System/Compatibility/usr/share/desktop-directories \
  /System/Compatibility/usr/share/applications \
  /Users/auzix/.e/e/applications \
  /Users/auzix/.cache/efreet \
  /System/Settings/ld.so.conf \
  /System/Settings/ld.so.cache; do
  if exists "${path}"; then
    stat -c 'OK %A %U:%G %n' "$(pp "${path}")" 2>/dev/null || printf 'OK %s\n' "${path}"
  else
    printf 'MISSING %s\n' "${path}"
  fi
done

section "desktop entry counts"
for dir in "${desktop_dirs[@]}"; do
  if [[ -d "$(pp "${dir}")" ]]; then
    count="$(find "$(pp "${dir}")" -maxdepth 1 -type f -name '*.desktop' 2>/dev/null | wc -l)"
    printf '%s %s\n' "${count}" "${dir}"
  else
    printf 'MISSING %s\n' "${dir}"
  fi
done

section "desktop Exec target audit"
tmp_entries="$(mktemp)"
trap 'rm -f "${tmp_entries}"' EXIT
for dir in "${desktop_dirs[@]}"; do
  [[ -d "$(pp "${dir}")" ]] || continue
  find "$(pp "${dir}")" -maxdepth 1 -type f -name '*.desktop' -print
done | sort -u >"${tmp_entries}"

if [[ ! -s "${tmp_entries}" ]]; then
  printf 'NO_DESKTOP_ENTRIES\n'
else
  while IFS= read -r desktop_file; do
    rel="${desktop_file}"
    [[ "${ROOT}" != "/" ]] && rel="${desktop_file#${ROOT}}"
    name="$(awk -F= '/^Name=/{print $2; exit}' "${desktop_file}" 2>/dev/null || true)"
    exec_line="$(awk -F= '/^Exec=/{print $2; exit}' "${desktop_file}" 2>/dev/null || true)"
    [[ -n "${exec_line}" ]] || {
      printf 'NOEXEC %s name=%s\n' "${rel}" "${name:-}"
      continue
    }
    cmd="${exec_line%% *}"
    cmd="${cmd%% %*}"
    case "${cmd}" in
      /*)
        if is_exec "${cmd}"; then
          printf 'OK %s name=%s exec=%s\n' "${rel}" "${name:-}" "${exec_line}"
        elif exists "${cmd}"; then
          printf 'NOT_EXEC %s name=%s exec=%s\n' "${rel}" "${name:-}" "${exec_line}"
        else
          printf 'MISSING_CMD %s name=%s exec=%s\n' "${rel}" "${name:-}" "${exec_line}"
        fi
        ;;
      *)
        printf 'PATH_CMD %s name=%s exec=%s\n' "${rel}" "${name:-}" "${exec_line}"
        ;;
    esac
  done <"${tmp_entries}"
fi

section "known launcher commands"
for cmd in \
  /System/Tools/launch-rescue-terminal \
  /System/Tools/launch-auzix-browser \
  /Programs/Terminology/current/Commands/terminology \
  /Programs/XTerm/current/Commands/xterm \
  /Programs/Midori/current/Commands/midori \
  /Programs/AuzixInstaller/current/Commands/auzix-installer \
  /Programs/AuzixDesktopIntegration/current/Commands/activate \
  /Programs/AuzixDesktopIntegration/current/Commands/e-launcher-sync; do
  if is_exec "${cmd}"; then
    printf 'OK_EXEC %s\n' "${cmd}"
  elif exists "${cmd}"; then
    printf 'NOT_EXEC %s\n' "${cmd}"
  else
    printf 'MISSING %s\n' "${cmd}"
  fi
done

section "ELF linker smoke"
ldd_bin=""
for candidate in /System/Compatibility/bin/ldd /Programs/Glibc/current/Commands/ldd /Programs/Libc6/current/Commands/ldd; do
  if is_exec "${candidate}"; then
    ldd_bin="$(pp "${candidate}")"
    break
  fi
done

if [[ -z "${ldd_bin}" ]]; then
  printf 'NO_LDD\n'
else
  for cmd in \
    /Programs/Terminology/current/Commands/terminology \
    /Programs/XTerm/current/Commands/xterm \
    /Programs/Midori/current/Commands/midori \
    /Programs/AuzixInstaller/current/Commands/auzix-installer; do
    [[ -x "$(pp "${cmd}")" ]] || continue
    printf -- '-- %s\n' "${cmd}"
    "${ldd_bin}" "$(pp "${cmd}")" 2>&1 | grep -E 'not found|undefined|error|ld-linux|libc|libeina|libelementary|libefl|libgtk|libX|libdbus' || true
  done
fi

section "recent desktop logs"
for log in \
  /System/Logs/display/start-e.log \
  /System/Logs/display/start-gui.log \
  /System/Logs/display/xorg.log \
  /System/Logs/display/efreetd.log \
  /Users/auzix/.e-log.log \
  /Users/auzix/.xsession-errors; do
  [[ -f "$(pp "${log}")" ]] || continue
  printf -- '-- %s\n' "${log}"
  tail -40 "$(pp "${log}")" 2>/dev/null || true
done
