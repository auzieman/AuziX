#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${ROOT_DIR}/profiles/packages/auzix-office-smoke.packages"
AUZIX_ROOT="${1:-}"

mapfile -t packages < <(awk 'NF && $1 !~ /^#/ {print $1}' "${PROFILE}" | sort -u)
[[ "${packages[*]}" == "abiword gnumeric" ]]
grep -F 'AUZIX_TRIXIE_REPORT' "${ROOT_DIR}/scripts/run-auzix-trixie-intake.sh" >/dev/null

if [[ -n "${AUZIX_ROOT}" ]]; then
  for package_name in "${packages[@]}"; do
    case "${package_name}" in
      abiword) native_name="AbiWord" ;;
      gnumeric) native_name="Gnumeric" ;;
    esac
    receipt="$(
      find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
        -name "${native_name}-*.auzix.json" -print -quit
    )"
    [[ -n "${receipt}" ]]
    jq -e --arg package "${package_name}" --arg name "${native_name}" '
      .name == $name
      and .migration_stage == "stage-1-compat-install"
      and .source.package == $package
      and (.paths.current == ("/Programs/" + $name + "/current"))
      and (.runtime_libraries | length == 1)
      and (.compatibility_exports | length >= 4)
    ' "${receipt}" >/dev/null

    prefix="$(jq -r '.prefix' "${receipt}")"
    loader="$(jq -r '.validation.loader' "${receipt}")"
    [[ -x "${AUZIX_ROOT}${prefix}/Commands/${package_name}" ]]
    [[ -x "${AUZIX_ROOT}${loader}" ]]
    LD_LIBRARY_PATH="${AUZIX_ROOT}${prefix}/Libraries" \
      "${AUZIX_ROOT}${loader}" \
      --library-path "${AUZIX_ROOT}${prefix}/Libraries" \
      "${AUZIX_ROOT}${prefix}/Commands/${package_name}.real" \
      --version >/dev/null 2>&1
  done
fi

echo "AuziX office package smoke contract: PASS"
