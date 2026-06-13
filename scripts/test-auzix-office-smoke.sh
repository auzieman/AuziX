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
    receipt="$(
      find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
        -name "Debian.${package_name}-*.auzix.json" -print -quit
    )"
    [[ -n "${receipt}" ]]
    jq -e --arg package "${package_name}" '
      .name == ("Debian." + $package)
      and .migration_stage == "stage-0-fhs-build"
      and .source.package == $package
      and (.paths.current | startswith("/Programs/DebianPackages/" + $package + "/"))
    ' "${receipt}" >/dev/null

    prefix="$(jq -r '.prefix' "${receipt}")"
    [[ -d "${AUZIX_ROOT}${prefix}/RootFS" ]]
    find "${AUZIX_ROOT}${prefix}/RootFS/usr/bin" -maxdepth 1 -type f \
      -name "${package_name}*" -print -quit | grep -q .
  done
fi

echo "AuziX office package smoke contract: PASS"
