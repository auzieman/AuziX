#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/extended-ports/AuZiXRoot}"
REPORT_DIR="${ROOT_DIR}/out/source-workbench/extended-ports"

mkdir -p "${AUZIX_ROOT}/System" "${AUZIX_ROOT}/Programs" "${REPORT_DIR}"

build_package() {
  local name="$1"
  local recipe="$2"
  rm -rf "${AUZIX_ROOT}/Programs/${name}"
  find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
    -name "${name}-*.auzix.json" -delete 2>/dev/null || true
  "${ROOT_DIR}/scripts/build-auzix-command-suite-package.sh" \
    "${AUZIX_ROOT}" "${ROOT_DIR}/packages/${recipe}"
}

build_package Conmon conmon.command-suite.json
build_package Crun crun.command-suite.json
build_package Netavark netavark.command-suite.json
build_package AardvarkDNS aardvark-dns.command-suite.json
rm -rf "${AUZIX_ROOT}/Programs/ContainersCommon"
find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
  -name 'ContainersCommon-*.auzix.json' -delete 2>/dev/null || true
"${ROOT_DIR}/scripts/build-auzix-containers-common-package.sh" "${AUZIX_ROOT}"
build_package Podman podman.command-suite.json

mapfile -t receipts < <(find "${AUZIX_ROOT}/System/PackageDB" -maxdepth 1 -type f \
  \( -name 'Conmon-*.auzix.json' -o -name 'Crun-*.auzix.json' \
     -o -name 'Netavark-*.auzix.json' -o -name 'AardvarkDNS-*.auzix.json' \
     -o -name 'ContainersCommon-*.auzix.json' \
     -o -name 'Podman-*.auzix.json' \) | sort)
[[ "${#receipts[@]}" -eq 6 ]]

jq -s '{format:"auzix-oci-runtime-slice-v1", status:"passed", packages:.}' \
  "${receipts[@]}" >"${REPORT_DIR}/oci-runtime.report.json"

printf '[oci-runtime] built Conmon, Crun, Netavark, AardvarkDNS, ContainersCommon, and Podman\n'
