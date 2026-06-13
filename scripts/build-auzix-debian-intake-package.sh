#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
DEBIAN_PACKAGE="${2:-}"
WORK_DIR="${ROOT_DIR}/out/auzix-packages/trixie/${DEBIAN_PACKAGE}"

log() {
  printf '[auzix-trixie-package] %s\n' "$*" >&2
}

[[ "${DEBIAN_PACKAGE}" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || {
  log "invalid Debian package name: ${DEBIAN_PACKAGE}"
  exit 1
}
[[ -d "${AUZIX_ROOT}/System/PackageDB" ]] || {
  log "AuziX root is missing: ${AUZIX_ROOT}"
  exit 1
}
for command_name in apt-get dpkg-deb jq rsync; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    log "missing command: ${command_name}"
    exit 1
  }
done

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}/debs" "${WORK_DIR}/extract"
(
  cd "${WORK_DIR}/debs"
  apt-get download "${DEBIAN_PACKAGE}" >/dev/null
)

deb_path="$(find "${WORK_DIR}/debs" -maxdepth 1 -type f -name '*.deb' -print -quit)"
[[ -n "${deb_path}" ]] || {
  log "no Debian archive downloaded for ${DEBIAN_PACKAGE}"
  exit 1
}

package_name="$(dpkg-deb -f "${deb_path}" Package)"
package_version="$(dpkg-deb -f "${deb_path}" Version)"
package_arch="$(dpkg-deb -f "${deb_path}" Architecture)"
package_description="$(dpkg-deb -f "${deb_path}" Description | sed -n '1p')"
package_depends="$(dpkg-deb -f "${deb_path}" Depends 2>/dev/null || true)"
safe_version="$(tr '/: ' '---' <<<"${package_version}" | tr -cd 'A-Za-z0-9_.+~-')"
program_root="${AUZIX_ROOT}/Programs/DebianPackages/${package_name}/${safe_version}"
receipt_path="${AUZIX_ROOT}/System/PackageDB/Debian.${package_name}-${safe_version}.auzix.json"

dpkg-deb -x "${deb_path}" "${WORK_DIR}/extract"
rm -rf "${program_root}"
mkdir -p "${program_root}/RootFS" "${program_root}/Metadata"
rsync -a "${WORK_DIR}/extract/" "${program_root}/RootFS/"
dpkg-deb -f "${deb_path}" >"${program_root}/Metadata/debian-control.txt"
ln -sfn "/Programs/DebianPackages/${package_name}/${safe_version}" \
  "${AUZIX_ROOT}/Programs/DebianPackages/${package_name}/current"

jq -n \
  --arg name "Debian.${package_name}" \
  --arg version "${safe_version}" \
  --arg source_package "${package_name}" \
  --arg source_version "${package_version}" \
  --arg source_architecture "${package_arch}" \
  --arg source_suite "trixie" \
  --arg upstream_depends "${package_depends}" \
  --arg description "${package_description}" \
  --arg prefix "/Programs/DebianPackages/${package_name}/${safe_version}" \
  --arg current "/Programs/DebianPackages/${package_name}/current" \
  '{
    name: $name,
    version: $version,
    kind: "program",
    migration_stage: "stage-0-fhs-build",
    prefix: $prefix,
    paths: {prefix: $prefix, current: $current},
    depends: [],
    description: $description,
    source: {
      type: "debian-binary-package",
      distribution: "debian",
      suite: $source_suite,
      package: $source_package,
      version: $source_version,
      architecture: $source_architecture,
      upstream_depends: $upstream_depends
    },
    notes: "Experimental Trixie intake package. The Debian payload is preserved under RootFS for later AuziX path-rule refinement."
  }' >"${receipt_path}"

log "built ${package_name} ${package_version}"
