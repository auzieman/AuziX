#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
ROOT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"

fail() {
  printf '[auzix-live-installer-demo] FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf '[auzix-live-installer-demo] PASS: %s\n' "$*" >&2
}

require_path() {
  local path="$1"
  [[ -e "${AUZIX_ROOT}${path}" || -L "${AUZIX_ROOT}${path}" ]] || fail "missing ${path}"
  pass "present ${path}"
}

resolve_staged_path() {
  local path="$1"
  local full="${AUZIX_ROOT}${path}"
  local target
  if [[ "${path}" =~ ^/Programs/([^/]+)/current(/.*)?$ ]]; then
    local package="${BASH_REMATCH[1]}"
    local suffix="${BASH_REMATCH[2]:-}"
    local current="${AUZIX_ROOT}/Programs/${package}/current"
    if [[ -L "${current}" ]]; then
      target="$(readlink "${current}")"
      case "${target}" in
        /*) full="${AUZIX_ROOT}${target}${suffix}" ;;
        *) full="$(dirname "${current}")/${target}${suffix}" ;;
      esac
      printf '%s\n' "${full}"
      return 0
    fi
  fi
  if [[ -L "${full}" ]]; then
    target="$(readlink "${full}")"
    case "${target}" in
      /*) full="${AUZIX_ROOT}${target}" ;;
      *) full="$(dirname "${full}")/${target}" ;;
    esac
  fi
  printf '%s\n' "${full}"
}

require_executable() {
  local path="$1"
  local full
  full="$(resolve_staged_path "${path}")"
  [[ -x "${full}" ]] || fail "missing executable ${path}"
  pass "executable ${path}"
}

require_desktop_exec() {
  local file="$1"
  local needle="$2"
  [[ -f "${AUZIX_ROOT}${file}" ]] || fail "missing desktop entry ${file}"
  grep -Fq "${needle}" "${AUZIX_ROOT}${file}" || fail "${file} lacks ${needle}"
  pass "desktop entry ${file} contains ${needle}"
}

require_path /Programs/Midori/current
require_executable /Programs/Midori/current/Commands/midori
require_path /Programs/AuzixInstallerEfl/current
require_executable /Programs/AuzixInstallerEfl/current/Commands/efl
require_path /Programs/AuzixPackageManagerEfl/current
require_executable /Programs/AuzixPackageManagerEfl/current/Commands/efl
require_path /Programs/DesktopAssets/auzietek
require_path /Programs/AuzixDesktopIntegration/current

installer_link="$(readlink "${AUZIX_ROOT}/System/Tools/launch-auzix-installer" 2>/dev/null || true)"
[[ "${installer_link}" == "/Programs/AuzixInstallerEfl/current/Commands/launch-auzix-installer" ]] ||
  fail "installer launcher is not the EFL frontend: ${installer_link:-not-a-link}"
pass "installer launcher points at EFL frontend"

require_executable /System/Tools/launch-auzix-browser
require_desktop_exec /System/Compatibility/usr/share/applications/auzix-midori.desktop "Exec=midori"
require_desktop_exec /System/Compatibility/usr/share/applications/auzix-browser.desktop /System/Tools/launch-auzix-browser
require_desktop_exec /Users/auzix/Desktop/Install\ AuziX.desktop /System/Tools/launch-auzix-installer

if ! find "${AUZIX_ROOT}/Programs/DesktopAssets/auzietek" -type f -name '*.edj' | grep -q .; then
  fail "DesktopAssets contains no Enlightenment/Elementary .edj themes"
fi
pass "DesktopAssets contains .edj theme assets"

printf '[auzix-live-installer-demo] live installer demo surface is staged\n' >&2
