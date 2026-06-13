#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
PACKAGE_VERSION="${AUZIX_PACKAGE_TOOLS_VERSION:-0.1}"
PROGRAM_ROOT="${AUZIX_ROOT}/Programs/AuzixPackageTools/${PACKAGE_VERSION}"
RUNTIME_LIB="${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu"
RUNTIME_LIB64="${AUZIX_ROOT}/System/Compatibility/lib64"
DEFAULT_REPO="${AUZIX_DEFAULT_REPO:-http://192.168.1.10/auzix/repo}"

log() {
  printf '[auzix-package-tools] %s\n' "$*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

copy_runtime_deps() {
  local binary="$1"
  local dep

  ldd "${binary}" 2>/dev/null |
    awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' |
    sort -u |
    while IFS= read -r dep; do
      [[ -e "${dep}" ]] || continue
      case "${dep}" in
        /lib64/*)
          install -D -m 0755 "${dep}" "${RUNTIME_LIB64}/$(basename "${dep}")"
          install -D -m 0755 "${dep}" "${PROGRAM_ROOT}/Libraries/$(basename "${dep}")"
          ;;
        /lib/x86_64-linux-gnu/*|/usr/lib/x86_64-linux-gnu/*)
          install -D -m 0755 "${dep}" "${RUNTIME_LIB}/$(basename "${dep}")"
          install -D -m 0755 "${dep}" "${PROGRAM_ROOT}/Libraries/$(basename "${dep}")"
          ;;
        *)
          install -D -m 0755 "${dep}" "${AUZIX_ROOT}${dep}"
          ;;
      esac
    done
}

if [[ ! -d "${AUZIX_ROOT}/System" ]]; then
  printf 'Auzix strict root is missing: %s\n' "${AUZIX_ROOT}" >&2
  exit 1
fi

for command_name in install jq ldd; do
  require_cmd "${command_name}"
done

rm -rf "${PROGRAM_ROOT}"
mkdir -p \
  "${PROGRAM_ROOT}/Commands" \
  "${PROGRAM_ROOT}/Libraries" \
  "${RUNTIME_LIB}" \
  "${RUNTIME_LIB64}" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/bin" \
  "${AUZIX_ROOT}/System/Settings/packages" \
  "${AUZIX_ROOT}/System/State/packages" \
  "${AUZIX_ROOT}/System/Logs/packages" \
  "${AUZIX_ROOT}/System/PackageDB" \
  "${AUZIX_ROOT}/System/Tools"

install -m 0755 "$(command -v jq)" "${PROGRAM_ROOT}/Commands/jq.real"
copy_runtime_deps "$(command -v jq)"
cat >"${PROGRAM_ROOT}/Commands/jq" <<'SCRIPT'
#!/System/Compatibility/bin/sh
export LD_LIBRARY_PATH="/Programs/AuzixPackageTools/current/Libraries:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
exec /Programs/AuzixPackageTools/current/Commands/jq.real "$@"
SCRIPT
chmod 0755 "${PROGRAM_ROOT}/Commands/jq"

cat > "${PROGRAM_ROOT}/Commands/auzix-pkg" <<'SCRIPT'
#!/System/Compatibility/bin/sh
set -eu

PATH=/Programs/AuzixPackageTools/current/Commands:/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox
JQ=/Programs/AuzixPackageTools/current/Commands/jq
SETTINGS=/System/Settings/packages
STATE=/System/State/packages
LOGS=/System/Logs/packages
REPO_CONF="${SETTINGS}/repositories.conf"
CACHE_INDEX="${STATE}/repo-index.json"
INSTALLED="${STATE}/installed.json"
WORK=/Work/Temp/auzix-pkg

usage() {
  cat <<'USAGE'
Usage:
  auzix-pkg refresh [REPOSITORY_URL]
  auzix-pkg list [all|available|installed]
  auzix-pkg info PACKAGE
  auzix-pkg bootstrap [PACKAGE ...]
  auzix-pkg install PACKAGE

Repository metadata is cached under /System/State/packages. Package archives
are checksum-verified before extraction. Removal is intentionally deferred
until every package carries a complete file-ownership manifest.
USAGE
}

die() {
  echo "auzix-pkg: $*" >&2
  exit 1
}

prepare_state() {
  "${BB}" mkdir -p "${SETTINGS}" "${STATE}" "${LOGS}" "${WORK}"
  if [ ! -s "${REPO_CONF}" ]; then
    echo "http://192.168.1.10/auzix/repo" >"${REPO_CONF}"
  fi
  if [ ! -s "${INSTALLED}" ]; then
    cat >"${INSTALLED}" <<'JSON'
{"format":"auzix-installed-v1","installed":[]}
JSON
  fi
}

repo_url() {
  "${BB}" sed -n '/^[[:space:]]*#/d; /^[[:space:]]*$/d; 1p' "${REPO_CONF}"
}

require_index() {
  [ -s "${CACHE_INDEX}" ] || die "repository cache is empty; run 'auzix-pkg refresh'"
  "${JQ}" -e '.format == "auzix-repo-v1" and (.packages | type == "array")' "${CACHE_INDEX}" >/dev/null ||
    die "repository cache has an unsupported format"
}

package_query() {
  package_name="$1"
  "${JQ}" -c --arg name "${package_name}" '
    [
      .packages[]
      | select((.name | ascii_downcase) == ($name | ascii_downcase))
    ]
    | last // empty
  ' "${CACHE_INDEX}"
}

is_installed() {
  package_name="$1"
  "${JQ}" -e --arg name "${package_name}" '
    any(.installed[]; (.name | ascii_downcase) == ($name | ascii_downcase))
  ' "${INSTALLED}" >/dev/null
}

record_install() {
  package_json="$1"
  source_url="$2"
  installed_at="$("${BB}" date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || "${BB}" date)"
  tmp_state="${INSTALLED}.tmp.$$"
  "${JQ}" \
    --argjson package "${package_json}" \
    --arg source "${source_url}" \
    --arg installed_at "${installed_at}" '
      .installed = (
        [.installed[] | select((.name | ascii_downcase) != ($package.name | ascii_downcase))]
        + [{
            name: $package.name,
            version: $package.version,
            kind: $package.kind,
            package: $package.package,
            sha256: $package.sha256,
            source: $source,
            installed_at: $installed_at
          }]
        | sort_by(.name | ascii_downcase)
      )
    ' "${INSTALLED}" >"${tmp_state}"
  "${BB}" mv "${tmp_state}" "${INSTALLED}"
}

validate_archive() {
  archive="$1"
  "${BB}" tar -tzf "${archive}" |
    "${BB}" awk '
      /^\// { bad=1 }
      /(^|\/)\.\.(\/|$)/ { bad=1 }
      END { exit bad }
    ' || die "unsafe path found in ${archive}"
}

run_post_install() {
  package_json="$1"
  hook="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.hooks.post_install // empty')"
  [ -n "${hook}" ] || return 0
  case "${hook}" in
    /Programs/*) ;;
    *) die "refusing post-install hook outside /Programs: ${hook}" ;;
  esac
  [ -x "${hook}" ] || die "post-install hook is missing or not executable: ${hook}"
  AUZIX_PACKAGE_NAME="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.name')" \
    AUZIX_PACKAGE_VERSION="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.version')" \
    "${hook}"
}

install_one() {
  requested="$1"
  stack="${2:-}"
  package_json="$(package_query "${requested}")"
  [ -n "${package_json}" ] || die "package not found in repository: ${requested}"

  name="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.name')"
  if is_installed "${name}"; then
    current="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.version')"
    current_sha="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.sha256')"
    installed_version="$("${JQ}" -r --arg name "${name}" '
      .installed[] | select((.name | ascii_downcase) == ($name | ascii_downcase)) | .version
    ' "${INSTALLED}" | "${BB}" head -n 1)"
    installed_sha="$("${JQ}" -r --arg name "${name}" '
      .installed[] | select((.name | ascii_downcase) == ($name | ascii_downcase)) | .sha256
    ' "${INSTALLED}" | "${BB}" head -n 1)"
    if [ "${current}" = "${installed_version}" ] && [ "${current_sha}" = "${installed_sha}" ]; then
      echo "${name} ${current} is already installed"
      return 0
    fi
  fi

  case " ${stack} " in
    *" ${name} "*) die "dependency cycle detected: ${stack} -> ${name}" ;;
  esac

  printf '%s\n' "${package_json}" | "${JQ}" -r '.depends[]?' |
    while IFS= read -r dependency; do
      [ -n "${dependency}" ] || continue
      if ! is_installed "${dependency}"; then
        install_one "${dependency}" "${stack} ${name}"
      fi
    done

  base_url="$(repo_url)"
  archive_name="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.package')"
  expected_sha="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.sha256')"
  archive="${WORK}/${archive_name}"
  source_url="${base_url%/}/packages/${archive_name}"

  echo "Fetching ${name} ${source_url}"
  curl -L --fail --show-error -o "${archive}.part" "${source_url}"
  "${BB}" mv "${archive}.part" "${archive}"

  actual_sha="$("${BB}" sha256sum "${archive}" | "${BB}" awk '{print $1}')"
  [ "${actual_sha}" = "${expected_sha}" ] ||
    die "checksum mismatch for ${archive_name}: expected ${expected_sha}, got ${actual_sha}"

  validate_archive "${archive}"
  "${BB}" tar -xzf "${archive}" -C /
  run_post_install "${package_json}"
  record_install "${package_json}" "${base_url}"
  echo "Installed ${name} $(printf '%s\n' "${package_json}" | "${JQ}" -r '.version')"
}

prepare_state
command_name="${1:-list}"
shift 2>/dev/null || true

case "${command_name}" in
  refresh)
    if [ "$#" -gt 0 ]; then
      echo "$1" >"${REPO_CONF}"
    fi
    url="$(repo_url)"
    [ -n "${url}" ] || die "no repository configured"
    curl -L --fail --show-error -o "${CACHE_INDEX}.tmp" "${url%/}/index.json"
    "${JQ}" -e '.format == "auzix-repo-v1" and (.packages | type == "array")' "${CACHE_INDEX}.tmp" >/dev/null ||
      die "downloaded repository index is invalid"
    "${BB}" mv "${CACHE_INDEX}.tmp" "${CACHE_INDEX}"
    echo "Refreshed ${url}: $("${JQ}" '.packages | length' "${CACHE_INDEX}") packages"
    ;;
  list)
    mode="${1:-all}"
    require_index
    case "${mode}" in
      installed)
        "${JQ}" -r '.installed[] | [.name, .version, .kind] | @tsv' "${INSTALLED}"
        ;;
      available)
        "${JQ}" -r --slurpfile state "${INSTALLED}" '
          .packages[]
          | select(.name as $name | any($state[0].installed[]; .name == $name) | not)
          | [.name, .version, .kind, ((.size / 1048576 * 10 | floor) / 10 | tostring) + " MiB"]
          | @tsv
        ' "${CACHE_INDEX}"
        ;;
      all)
        "${JQ}" -r --slurpfile state "${INSTALLED}" '
          .packages[]
          | . as $package
          | [$package.name, $package.version, $package.kind,
             (if any($state[0].installed[]; .name == $package.name) then "installed" else "available" end)]
          | @tsv
        ' "${CACHE_INDEX}"
        ;;
      *) die "unknown list mode: ${mode}" ;;
    esac
    ;;
  info)
    require_index
    [ "$#" -eq 1 ] || die "info requires a package name"
    package_json="$(package_query "$1")"
    [ -n "${package_json}" ] || die "package not found: $1"
    printf '%s\n' "${package_json}" | "${JQ}" .
    ;;
  bootstrap)
    require_index
    tmp_state="${INSTALLED}.tmp.$$"
    printf '%s\n' "$@" | "${JQ}" -Rsc 'split("\n") | map(select(length > 0) | ascii_downcase)' >"${WORK}/excludes.json"
    "${JQ}" --slurpfile excludes "${WORK}/excludes.json" '
      {
        format: "auzix-installed-v1",
        installed: [
          .packages[]
          | select((.name | ascii_downcase) as $name | ($excludes[0] | index($name)) == null)
          | {
              name,
              version,
              kind,
              package,
              sha256,
              source: "base-image",
              installed_at: "base-image"
            }
        ]
      }
    ' "${CACHE_INDEX}" >"${tmp_state}"
    "${BB}" mv "${tmp_state}" "${INSTALLED}"
    echo "Bootstrapped $("${JQ}" '.installed | length' "${INSTALLED}") installed package records"
    ;;
  install)
    require_index
    [ "$#" -eq 1 ] || die "install requires a package name"
    install_one "$1" ""
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
SCRIPT
chmod 0755 "${PROGRAM_ROOT}/Commands/auzix-pkg"

ln -sfn "/Programs/AuzixPackageTools/${PACKAGE_VERSION}" "${AUZIX_ROOT}/Programs/AuzixPackageTools/current"
ln -sfn /Programs/AuzixPackageTools/current/Commands/jq "${AUZIX_ROOT}/System/Compatibility/bin/jq"
ln -sfn /Programs/AuzixPackageTools/current/Commands/jq "${AUZIX_ROOT}/System/Compatibility/usr/bin/jq"
ln -sfn /Programs/AuzixPackageTools/current/Commands/auzix-pkg "${AUZIX_ROOT}/System/Compatibility/bin/auzix-pkg"
ln -sfn /Programs/AuzixPackageTools/current/Commands/auzix-pkg "${AUZIX_ROOT}/System/Compatibility/usr/bin/auzix-pkg"
ln -sfn /Programs/AuzixPackageTools/current/Commands/auzix-pkg "${AUZIX_ROOT}/System/Tools/auzix-pkg"

cat >"${AUZIX_ROOT}/System/Settings/packages/repositories.conf" <<EOF
${DEFAULT_REPO}
EOF

cat >"${AUZIX_ROOT}/System/PackageDB/AuzixPackageTools-${PACKAGE_VERSION}.auzix.json" <<EOF
{
  "name": "AuzixPackageTools",
  "version": "${PACKAGE_VERSION}",
  "kind": "system",
  "migration_stage": "stage-1-core-package-management",
  "prefix": "/Programs/AuzixPackageTools/${PACKAGE_VERSION}",
  "depends": [
    "BusyBox",
    "Curl"
  ],
  "commands": [
    "/Programs/AuzixPackageTools/${PACKAGE_VERSION}/Commands/auzix-pkg",
    "/Programs/AuzixPackageTools/${PACKAGE_VERSION}/Commands/jq",
    "/Programs/AuzixPackageTools/${PACKAGE_VERSION}/Commands/jq.real"
  ],
  "paths": {
    "current": "/Programs/AuzixPackageTools/current",
    "libraries": "/Programs/AuzixPackageTools/${PACKAGE_VERSION}/Libraries"
  },
  "runtime_state": "/System/State/packages",
  "runtime_logs": "/System/Logs/packages",
  "compatibility_exports": [
    "/System/Compatibility/bin/auzix-pkg",
    "/System/Compatibility/bin/jq",
    "/System/Compatibility/usr/bin/auzix-pkg",
    "/System/Compatibility/usr/bin/jq",
    "/System/Tools/auzix-pkg"
  ],
  "notes": "First Auzix repository client and transaction-state manager. JSON remains the interchange and local-cache format; a future Lua GUI will use the same files."
}
EOF

log "Auzix package tools installed at ${PROGRAM_ROOT}"
