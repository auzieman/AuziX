#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:?usage: build-auzix-installed-debian-package.sh ROOT DEBIAN_PACKAGE}"
DEBIAN_PACKAGE="${2:?usage: build-auzix-installed-debian-package.sh ROOT DEBIAN_PACKAGE}"

log() {
  printf '[auzix-installed-dpkg] %s\n' "$*" >&2
}

for command_name in dpkg-query jq rsync; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    log "missing command: ${command_name}"
    exit 1
  }
done

native_name="$("${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" --print-native-name "${DEBIAN_PACKAGE}")"
package_version="$(dpkg-query -W -f='${Version}' "${DEBIAN_PACKAGE}")"
package_arch="$(dpkg-query -W -f='${Architecture}' "${DEBIAN_PACKAGE}")"
package_description="$(dpkg-query -W -f='${binary:Summary}' "${DEBIAN_PACKAGE}" 2>/dev/null || true)"
package_predepends="$(dpkg-query -W -f='${Pre-Depends}' "${DEBIAN_PACKAGE}" 2>/dev/null || true)"
package_depends="$(dpkg-query -W -f='${Depends}' "${DEBIAN_PACKAGE}" 2>/dev/null || true)"
safe_version="$(tr '/: ' '---' <<<"${package_version}" | tr -cd 'A-Za-z0-9_.+~-')"

program_root="${AUZIX_ROOT}/Programs/${native_name}/${safe_version}"
receipt_path="${AUZIX_ROOT}/System/PackageDB/${native_name}-${safe_version}.auzix.json"
rm -rf "${program_root}"
mkdir -p "${program_root}/RootFS" "${program_root}/Metadata" "${AUZIX_ROOT}/System/PackageDB"

dpkg-query -s "${DEBIAN_PACKAGE}" >"${program_root}/Metadata/debian-control.txt"

while IFS= read -r installed_path; do
  [[ "${installed_path}" == /* && -f "${installed_path}" ]] || continue
  mkdir -p "${program_root}/RootFS/$(dirname "${installed_path#/}")"
  rsync -a "${installed_path}" "${program_root}/RootFS/${installed_path#/}"
done < <(dpkg-query -L "${DEBIAN_PACKAGE}")

ln -sfn "/Programs/${native_name}/${safe_version}" "${AUZIX_ROOT}/Programs/${native_name}/current"

depends_text="${package_predepends}${package_predepends:+, }${package_depends}"
depends_json="$(
  tr ',' '\n' <<<"${depends_text}" |
    while IFS= read -r dep; do
      selected=""
      while IFS= read -r alternative; do
        clean="$(sed -E 's/[[:space:]]*\([^)]*\)//g; s/^[[:space:]]+//; s/[[:space:]]+$//; s/:[A-Za-z0-9_-]+$//' <<<"${alternative}")"
        [[ "${clean}" =~ ^[a-z0-9][a-z0-9+_.-]*$ ]] || continue
        case "${clean}" in
          default-dbus-system-bus|dbus-system-bus)
            clean="dbus"
            ;;
        esac
        if dpkg-query -W -f='${db:Status-Abbrev}' "${clean}" 2>/dev/null | grep -q '^ii '; then
          selected="${clean}"
          break
        fi
        [[ -n "${selected}" ]] || selected="${clean}"
      done < <(tr '|' '\n' <<<"${dep}")
      [[ -n "${selected}" ]] || continue
      "${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh" --print-native-name "${selected}"
    done |
    awk 'NF && !seen[$0]++' |
    jq -R -s 'split("\n") | map(select(length > 0))'
)"

payload_file_count="$(find "${program_root}/RootFS" -type f | wc -l | tr -d ' ')"
payload_size_bytes="$(du -sb "${program_root}/RootFS" | awk '{print $1}')"

jq -n \
  --arg name "${native_name}" \
  --arg version "${package_version}" \
  --arg safe_version "${safe_version}" \
  --arg package "${DEBIAN_PACKAGE}" \
  --arg architecture "${package_arch}" \
  --arg description "${package_description:-Installed dpkg repack}" \
  --arg upstream_depends "${depends_text}" \
  --argjson depends "${depends_json}" \
  --argjson payload_file_count "${payload_file_count}" \
  --argjson payload_size_bytes "${payload_size_bytes}" \
  '{
    name: $name,
    version: $version,
    kind: "staging",
    migration_stage: "stage-1-installed-dpkg-repack",
    prefix: ("/Programs/" + $name + "/" + $safe_version),
    paths: {
      prefix: ("/Programs/" + $name + "/" + $safe_version),
      current: ("/Programs/" + $name + "/current")
    },
    depends: $depends,
    recommends: [],
    commands: [],
    compatibility_exports: [],
    runtime_ladder: {
      local_rootfs: true,
      dependency_packages: $depends,
      system_surfaces: ["/System/Libraries", "/System/Compatibility", "/System/Settings"]
    },
    description: $description,
    source: {
      type: "installed-debian-package",
      distribution: "debian",
      suite: "trixie",
      package: $package,
      version: $version,
      architecture: $architecture,
      control_file: ("/Programs/" + $name + "/" + $safe_version + "/Metadata/debian-control.txt"),
      upstream_depends: $upstream_depends,
      payload_file_count: $payload_file_count,
      payload_size_bytes: $payload_size_bytes,
      repack_class: "installed-payload"
    },
    notes: "Bridge package emitted from the installed Trixie builder dpkg database when apt-get download has no configured archive source. Replace with source/intake output when available."
  }' >"${receipt_path}"

log "built ${native_name} ${package_version} from installed ${DEBIAN_PACKAGE} (${payload_file_count} files)"
