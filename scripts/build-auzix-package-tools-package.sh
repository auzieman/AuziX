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
chown 0:1000 \
  "${AUZIX_ROOT}/System/State/packages" \
  "${AUZIX_ROOT}/System/Logs/packages" 2>/dev/null || true
chmod 0775 \
  "${AUZIX_ROOT}/System/State/packages" \
  "${AUZIX_ROOT}/System/Logs/packages"

install -m 0755 "$(command -v jq)" "${PROGRAM_ROOT}/Commands/jq.real"
copy_runtime_deps "$(command -v jq)"
cat >"${PROGRAM_ROOT}/Commands/jq" <<'SCRIPT'
#!/System/Compatibility/bin/sh
exec /Programs/AuzixPackageTools/current/Libraries/ld-linux-x86-64.so.2 \
  --library-path /Programs/AuzixPackageTools/current/Libraries \
  /Programs/AuzixPackageTools/current/Commands/jq.real "$@"
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
PROVIDED="${WORK}/provided.names"
BLOCKED="${WORK}/transaction.blocked"

usage() {
  cat <<'USAGE'
Usage:
  auzix-pkg refresh [REPOSITORY_URL]
  auzix-pkg list [all|available|installed|long]
  auzix-pkg info PACKAGE
  auzix-pkg status PACKAGE
  auzix-pkg files PACKAGE
  auzix-pkg owner PATH
  auzix-pkg env PACKAGE
  auzix-pkg bootstrap [PACKAGE ...]
  auzix-pkg bootstrap-manifest FILE
  auzix-pkg bootstrap-receipts [DIRECTORY]
  auzix-pkg bootstrap-runtime-substrate
  auzix-pkg plan PACKAGE
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

fetch_url() {
  url="$1"
  output="$2"
  if [ -x "${BB}" ]; then
    "${BB}" wget -O "${output}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${output}" "${url}"
  elif command -v curl >/dev/null 2>&1; then
    curl -L --fail --show-error -o "${output}" "${url}"
  elif [ -x /Programs/Curl/current/Commands/curl ]; then
    /Programs/Curl/current/Commands/curl -L --fail --show-error -o "${output}" "${url}"
  else
    die "no usable downloader found"
  fi
}

prepare_state() {
  "${BB}" mkdir -p "${SETTINGS}" "${STATE}" "${LOGS}" "${WORK}"
  if [ ! -s "${REPO_CONF}" ]; then
    echo "@AUZIX_DEFAULT_REPO@" >"${REPO_CONF}"
  fi
  if [ ! -s "${INSTALLED}" ]; then
    "${BB}" tee "${INSTALLED}" >/dev/null <<'JSON'
{"format":"auzix-installed-v1","installed":[]}
JSON
  fi
  : >"${PROVIDED}"
  : >"${BLOCKED}"
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

installed_query() {
  package_name="$1"
  "${JQ}" -c --arg name "${package_name}" '
    [
      .installed[]
      | select((.name | ascii_downcase) == ($name | ascii_downcase))
    ]
    | last // empty
  ' "${INSTALLED}"
}

package_receipt_path() {
  package_json="$1"
  receipt_path="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.receipt // empty')"
  [ -n "${receipt_path}" ] || return 1
  printf '%s\n' "${receipt_path}"
}

package_file_list() {
  package_json="$1"
  receipt_path="$(package_receipt_path "${package_json}" || true)"
  if [ -n "${receipt_path}" ] && [ -s "${receipt_path}" ]; then
    "${JQ}" -r '
      [
        .prefix?,
        .paths?.prefix?,
        .paths?.current?,
        (.commands[]?),
        (.desktop_entries[]?),
        (.compatibility_exports[]?),
        .service?,
        .hooks?.post_install?,
        .runtime_state?,
        .runtime_logs?
      ]
      | map(select(type == "string" and length > 0))
      | unique[]
    ' "${receipt_path}"
    prefix="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.prefix // empty')"
    if [ -n "${prefix}" ] && [ -d "${prefix}" ]; then
      "${BB}" find "${prefix}" -mindepth 1 -print 2>/dev/null || true
    fi
  else
    printf '%s\n' "${package_json}" | "${JQ}" -r '
      [
        .prefix?,
        (.commands[]?),
        (.desktop_entries[]?),
        (.compatibility_exports[]?),
        .service?,
        .hooks?.post_install?
      ]
      | map(select(type == "string" and length > 0))
      | unique[]
    '
  fi
}

package_runtime_env() {
  package_json="$1"
  printf '%s\n' "${package_json}" | "${JQ}" '
    def rootfs_paths($root):
      {
        PATH: [
          ($root + "/usr/bin"),
          ($root + "/usr/sbin"),
          ($root + "/bin"),
          ($root + "/sbin")
        ],
        LD_LIBRARY_PATH: [
          ($root + "/usr/lib/x86_64-linux-gnu"),
          ($root + "/usr/lib"),
          ($root + "/lib/x86_64-linux-gnu"),
          ($root + "/lib")
        ],
        XDG_DATA_DIRS: [($root + "/usr/share")],
        GSETTINGS_SCHEMA_DIR: [($root + "/usr/share/glib-2.0/schemas")],
        GI_TYPELIB_PATH: [
          ($root + "/usr/lib/x86_64-linux-gnu/girepository-1.0"),
          ($root + "/usr/lib/girepository-1.0")
        ]
      };
    . as $package
    | ($package.prefix // "") as $prefix
    | ($prefix + "/RootFS") as $root
    | {
        package: $package.name,
        prefix: $prefix,
        commands: ($package.commands // []),
        runtime_ladder: ($package.runtime_ladder // null),
        dependency_roots: (($package.runtime_ladder.dependency_packages // $package.depends // []) | map("/Programs/" + . + "/current/RootFS")),
        values: (
          rootfs_paths($root)
          + {
              PATH: ([($prefix + "/Commands")] + rootfs_paths($root).PATH + ["/Programs/BusyBox/current/Commands", "/System/Compatibility/bin", "/System/Compatibility/usr/bin"]),
              LD_LIBRARY_PATH: (rootfs_paths($root).LD_LIBRARY_PATH + ["/System/Compatibility/usr/lib/x86_64-linux-gnu", "/System/Compatibility/lib/x86_64-linux-gnu", "/System/Compatibility/lib64", "/System/Libraries"]),
              XDG_DATA_DIRS: (rootfs_paths($root).XDG_DATA_DIRS + ["/System/Compatibility/usr/share"])
            }
        )
      }
  '
}

is_installed() {
  package_name="$1"
  "${JQ}" -e --arg name "${package_name}" '
    any(.installed[]; (.name | ascii_downcase) == ($name | ascii_downcase))
  ' "${INSTALLED}" >/dev/null
}

receipt_installed_by_name() {
  package_name="$1"
  safe_name="$(printf '%s\n' "${package_name}" | "${BB}" sed 's/[][*?.^$\\]/_/g')"
  for receipt in "/System/PackageDB/${safe_name}-"*.auzix.json "/System/PackageDB/${safe_name}.auzix.json"; do
    [ -s "${receipt}" ] && return 0
  done
  return 1
}

program_present_by_name() {
  package_name="$1"
  [ -e "/Programs/${package_name}/current" ] || [ -d "/Programs/${package_name}" ]
}

active_glibc_version() {
  [ -x /System/Libraries/Runtime/glibc/libc.so.6 ] || return 1
  /System/Libraries/Runtime/glibc/libc.so.6 2>&1 |
    "${BB}" awk '''/release version/ { print $NF; found=1; exit } /GNU C Library/ && !found { for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+[.][0-9]+/) { print $i; found=1; exit } } END { exit found ? 0 : 1 }''' |
    "${BB}" sed 's/[^0-9.].*$//'
}

base_runtime_provides() {
  package_name="$1"
  case "${package_name}" in
    Libc6|LibgccS1|GCC14Base)
      [ -x /System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2 ] &&
      [ -x /System/Libraries/Runtime/glibc/libc.so.6 ]
      ;;
    *) return 1 ;;
  esac
}

core_runtime_package() {
  package_name="$1"
  case "${package_name}" in
    Libc6|LibgccS1|GCC14Base) return 0 ;;
    *) return 1 ;;
  esac
}

core_runtime_dependency_satisfied() {
  package_name="$1"
  core_runtime_package "${package_name}" || return 1
  base_runtime_provides "${package_name}" || return 1
  record_base_runtime_provider "${package_name}" >/dev/null 2>&1 || true
  provided_mark "${package_name}"
  return 0
}

substrate_package() {
  package_name="$1"
  case "${package_name}" in
    Libc6|LibgccS1|GCC14Base|Libstdc6|Libatomic1|Libseccomp2|Zlib1g|OpenSSL|Libssl*|Libcrypto*|CACerts|CaCertificates|Curl|Libcurl*|DBus|Libdbus*|PAM|Libpam*|Polkit|Udev|Systemd|Xorg|XorgServer|Xserver*|Libx*|Libxcb*|Libinput*|Libdrm*|Mesa*|Libgl*|Libegl*|Wayland*|EFL|Enlightenment|Terminology|Libeina*|Libecore*|Libevas*|Libedje*|Libefreet*|Libelementary*|Libeet*|Libeio*|Libemotion*|Libelput*|Libeeze*|GLib|Libglib*|GTK*|Libgtk*|Gnome*|GSettings*|Dconf*|DesktopFileUtils|SharedMimeInfo|GtkUpdateIconCache|GdkPixbuf*|Fontconfig|Freetype|Pango|Cairo|Harfbuzz*)
      return 0
      ;;
    *) return 1 ;;
  esac
}

record_base_runtime_provider() {
  package_name="$1"
  base_runtime_provides "${package_name}" || return 1
  version="base-runtime"
  case "${package_name}" in
    Libc6) version="$(active_glibc_version 2>/dev/null || echo base-runtime)"; record_name="ActiveBaseRuntimeLibc6" ;;
    LibgccS1) version="$(active_glibc_version 2>/dev/null || echo base-runtime)-glibc-stratum"; record_name="ActiveBaseRuntimeLibgcc" ;;
    GCC14Base) version="$(active_glibc_version 2>/dev/null || echo base-runtime)-glibc-stratum"; record_name="ActiveBaseRuntimeGCC" ;;
    *) return 1 ;;
  esac
  tmp_state="${INSTALLED}.tmp.$$"
  "${JQ}" \
    --arg name "${record_name}" \
    --arg provided "active-runtime:${package_name}" \
    --arg version "${version}" '''
      .installed = (
        [.installed[] | select((.name | ascii_downcase) != ($name | ascii_downcase))]
        + [{
            name: $name,
            version: $version,
            kind: "runtime-substrate",
            package: "active-base-runtime",
            sha256: "",
            description: "Active AUZiX base runtime substrate provider. Normal packages must build against this core runtime; alternate glibc packages are not valid leaf-install dependencies.",
            receipt: "/System/State/packages/installed.json",
            prefix: "/System/Libraries/Runtime/glibc",
            commands: [],
            desktop_entries: [],
            compatibility_exports: [],
            depends: [],
            recommends: [],
            provides: [$provided],
            substrate: {tier: "base-runtime", scope: "active-runtime", protected: true, satisfies_package_dependencies: true, single_core_glibc: true},
            source: "active-base-runtime",
            installed_at: "active-base-runtime"
          }]
        | sort_by(.name | ascii_downcase)
      )
    ''' "${INSTALLED}" >"${tmp_state}"
  "${BB}" mv "${tmp_state}" "${INSTALLED}"
  provided_mark "active-runtime:${package_name}"
  provided_mark "${package_name}"
}

provided_has() {
  "${BB}" grep -Fxq "$1" "${PROVIDED}" 2>/dev/null
}

reset_transaction_marks() {
  : >"${PROVIDED}"
  : >"${BLOCKED}"
}

provided_mark() {
  provided_name="$1"
  [ -n "${provided_name}" ] || return 0
  provided_has "${provided_name}" || echo "${provided_name}" >>"${PROVIDED}"
}

mark_runtime_block() {
  blocked_message="$1"
  printf '%s\n' "${blocked_message}" >>"${BLOCKED}"
}

fail_if_blocked() {
  if [ -s "${BLOCKED}" ]; then
    first_block="$("${BB}" head -n 1 "${BLOCKED}")"
    die "${first_block}"
  fi
}

record_installed_name() {
  package_name="$1"
  source_label="${2:-manifest}"
  package_json="$(package_query "${package_name}" || true)"
  [ -n "${package_json}" ] || return 1
  tmp_state="${INSTALLED}.tmp.$$"
  package_state="${WORK}/record-installed-name.$$.json"
  printf '%s\n' "${package_json}" >"${package_state}"
  "${JQ}" \
    --slurpfile package_state "${package_state}" \
    --arg source "${source_label}" '
      ($package_state[0]) as $package
      |
      .installed = (
        [.installed[] | select((.name | ascii_downcase) != ($package.name | ascii_downcase))]
        + [{
            name: $package.name,
            version: $package.version,
            kind: $package.kind,
            package: $package.package,
            sha256: $package.sha256,
            description: ($package.description // ""),
            receipt: $package.receipt,
            prefix: $package.prefix,
            commands: ($package.commands // []),
            desktop_entries: ($package.desktop_entries // []),
            compatibility_exports: ($package.compatibility_exports // []),
            depends: ($package.depends // []),
            recommends: ($package.recommends // []),
            provides: ($package.provides // []),
            substrate: ($package.substrate // null),
            source_metadata: ($package.source // {}),
            runtime_ladder: ($package.runtime_ladder // null),
            runtime_environment: ($package.runtime_environment // null),
            permissions: ($package.permissions // null),
            validation: ($package.validation // null),
            source: $source,
            installed_at: $source
          }]
        | sort_by(.name | ascii_downcase)
      )
    ' "${INSTALLED}" >"${tmp_state}"
  "${BB}" rm -f "${package_state}"
  "${BB}" mv "${tmp_state}" "${INSTALLED}"
  provided_mark "${package_name}"
}

record_receipt_file() {
  receipt_file="$1"
  source_label="${2:-receipt-bootstrap}"
  [ -s "${receipt_file}" ] || return 1
  tmp_state="${INSTALLED}.tmp.$$"
  "${JQ}" \
    --slurpfile package_state "${receipt_file}" \
    --arg receipt "${receipt_file}" \
    --arg source "${source_label}" '
      ($package_state[0]) as $package
      | select(($package.name // "") != "")
      |
      .installed = (
        [.installed[] | select((.name | ascii_downcase) != ($package.name | ascii_downcase))]
        + [{
            name: $package.name,
            version: ($package.version // "unknown"),
            kind: ($package.kind // "unknown"),
            package: ($package.package // ""),
            sha256: ($package.sha256 // ""),
            description: ($package.description // $package.notes // ""),
            receipt: $receipt,
            prefix: ($package.prefix // $package.paths.prefix // ""),
            commands: ($package.commands // []),
            desktop_entries: ($package.desktop_entries // []),
            compatibility_exports: ($package.compatibility_exports // []),
            depends: ($package.depends // []),
            recommends: ($package.recommends // []),
            provides: ($package.provides // []),
            source_metadata: ($package.source // {}),
            runtime_ladder: ($package.runtime_ladder // null),
            runtime_environment: ($package.runtime_environment // null),
            permissions: ($package.permissions // null),
            validation: ($package.validation // null),
            source: $source,
            installed_at: $source
          }]
        | sort_by(.name | ascii_downcase)
      )
    ' "${INSTALLED}" >"${tmp_state}" || return 1
  "${BB}" mv "${tmp_state}" "${INSTALLED}"
  receipt_name="$("${JQ}" -r '.name // empty' "${receipt_file}" 2>/dev/null || true)"
  [ -n "${receipt_name}" ] && provided_mark "${receipt_name}"
}

seed_provided_state() {
  "${JQ}" -r '.installed[]?.name // empty' "${INSTALLED}" 2>/dev/null |
    while IFS= read -r installed_name; do
      [ -n "${installed_name}" ] && provided_mark "${installed_name}"
    done
  "${JQ}" -r '.installed[]?.provides[]? // empty' "${INSTALLED}" 2>/dev/null |
    while IFS= read -r provided_name; do
      [ -n "${provided_name}" ] && provided_mark "${provided_name}"
    done
  for receipt in /System/PackageDB/*.auzix.json /System/PackageDB/*.json; do
    [ -s "${receipt}" ] || continue
    receipt_name="$("${JQ}" -r '.name // empty' "${receipt}" 2>/dev/null || true)"
    [ -n "${receipt_name}" ] && [ "${receipt_name}" != null ] && provided_mark "${receipt_name}"
    "${JQ}" -r '.provides[]? // empty' "${receipt}" 2>/dev/null |
      while IFS= read -r provided_name; do
        [ -n "${provided_name}" ] && provided_mark "${provided_name}"
      done
  done
  if [ -d /Programs ]; then
    for program_dir in /Programs/*; do
      [ -d "${program_dir}" ] || continue
      provided_mark "${program_dir##*/}"
    done
  fi
  for base_name in Libc6 LibgccS1 GCC14Base; do
    if base_runtime_provides "${base_name}"; then
      record_base_runtime_provider "${base_name}" >/dev/null 2>&1 || provided_mark "${base_name}"
    fi
  done
}

dependency_satisfied() {
  package_name="$1"
  core_runtime_dependency_satisfied "${package_name}" ||
  provided_has "${package_name}" ||
  is_installed "${package_name}" ||
  receipt_installed_by_name "${package_name}" ||
  program_present_by_name "${package_name}"
}

receipt_installed() {
  package_json="$1"
  receipt="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.receipt // empty')"
  [ -n "${receipt}" ] && [ -s "${receipt}" ]
}

record_install() {
  package_json="$1"
  source_url="$2"
  installed_at="$("${BB}" date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || "${BB}" date)"
  tmp_state="${INSTALLED}.tmp.$$"
  package_state="${WORK}/record-install-package.$$.json"
  printf '%s\n' "${package_json}" >"${package_state}"
  "${JQ}" \
    --slurpfile package_state "${package_state}" \
    --arg source "${source_url}" \
    --arg installed_at "${installed_at}" '
      ($package_state[0]) as $package
      |
      .installed = (
        [.installed[] | select((.name | ascii_downcase) != ($package.name | ascii_downcase))]
        + [{
            name: $package.name,
            version: $package.version,
            kind: $package.kind,
            package: $package.package,
            sha256: $package.sha256,
            description: ($package.description // ""),
            receipt: $package.receipt,
            prefix: $package.prefix,
            commands: ($package.commands // []),
            desktop_entries: ($package.desktop_entries // []),
            compatibility_exports: ($package.compatibility_exports // []),
            depends: ($package.depends // []),
            recommends: ($package.recommends // []),
            provides: ($package.provides // []),
            substrate: ($package.substrate // null),
            source_metadata: ($package.source // {}),
            runtime_ladder: ($package.runtime_ladder // null),
            runtime_environment: ($package.runtime_environment // null),
            permissions: ($package.permissions // null),
            validation: ($package.validation // null),
            source: $source,
            installed_at: $installed_at
          }]
        | sort_by(.name | ascii_downcase)
      )
    ' "${INSTALLED}" >"${tmp_state}"
  "${BB}" rm -f "${package_state}"
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
  hook_path="${hook%% *}"
  [ -x "${hook_path}" ] || die "post-install hook is missing or not executable: ${hook_path}"
  AUZIX_PACKAGE_NAME="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.name')" \
    AUZIX_PACKAGE_VERSION="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.version')" \
    /System/Compatibility/bin/sh -c "${hook}"
}

install_one() {
  requested="$1"
  stack="${2:-}"
  package_json="$(package_query "${requested}")"
  [ -n "${package_json}" ] || die "package not found in repository: ${requested}"

  name="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.name')"
  if core_runtime_dependency_satisfied "${name}"; then
    echo "${name} is satisfied by the active AUZiX core glibc runtime; not installing an alternate glibc package"
    return 0
  fi
  if receipt_installed "${package_json}" && ! is_installed "${name}"; then
    echo "${name} receipt exists; recording installed state"
    record_install "${package_json}" "$(repo_url)"
    provided_mark "${name}"
    return 0
  fi
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
      provided_mark "${name}"
      return 0
    fi
  fi

  case " ${stack} " in
    *" ${name} "*)
      echo "Dependency cycle already in progress: ${stack} -> ${name}; continuing current install wave"
      return 0
      ;;
  esac

  if [ "${AUZIX_SKIP_DEPS:-0}" != "1" ]; then
    printf '%s\n' "${package_json}" | "${JQ}" -r '.depends[]? | select(. != null and . != "")' |
      while IFS= read -r dependency; do
        [ -n "${dependency}" ] || continue
        [ "${dependency}" != "null" ] || continue
        if [ "${dependency}" = "${name}" ]; then
          echo "Skipping self dependency for ${name}"
          continue
        fi
        if ! dependency_satisfied "${dependency}"; then
          install_one "${dependency}" "${stack} ${name}"
        else
          echo "Dependency ${dependency} already satisfied; not reinstalling"
        fi
      done
    fail_if_blocked
  fi

  base_url="$(repo_url)"
  archive_name="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.package')"
  expected_sha="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.sha256')"
  archive="${WORK}/${archive_name}"
  source_url="${base_url%/}/packages/${archive_name}"

  echo "Fetching ${name} ${source_url}"
  fetch_url "${source_url}" "${archive}.part"
  "${BB}" mv "${archive}.part" "${archive}"

  actual_sha="$("${BB}" sha256sum "${archive}" | "${BB}" awk '{print $1}')"
  [ "${actual_sha}" = "${expected_sha}" ] ||
    die "checksum mismatch for ${archive_name}: expected ${expected_sha}, got ${actual_sha}"

  validate_archive "${archive}"
  "${BB}" tar -xzpf "${archive}" -C /
  if [ -x /System/Tools/finalize-installed-root ]; then
    /System/Tools/finalize-installed-root /
  fi
  run_post_install "${package_json}"
  record_install "${package_json}" "${base_url}"
  provided_mark "${name}"
  echo "Installed ${name} $(printf '%s\n' "${package_json}" | "${JQ}" -r '.version')"
}

plan_one() {
  requested="$1"
  stack="${2:-}"
  package_json="$(package_query "${requested}")"
  [ -n "${package_json}" ] || die "package not found in repository: ${requested}"
  name="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.name')"

  dependency_satisfied "${name}" && return 0
  provided_has "plan:${name}" && return 0
  case " ${stack} " in
    *" ${name} "*) return 0 ;;
  esac

  if [ "${AUZIX_SKIP_DEPS:-0}" != "1" ]; then
    printf '%s\n' "${package_json}" | "${JQ}" -r '.depends[]? | select(. != null and . != "")' |
      while IFS= read -r dependency; do
        [ -n "${dependency}" ] || continue
        [ "${dependency}" != "null" ] || continue
        [ "${dependency}" = "${name}" ] && continue
        if ! dependency_satisfied "${dependency}"; then
          plan_one "${dependency}" "${stack} ${name}"
        fi
      done
    fail_if_blocked
  fi

  if ! dependency_satisfied "${name}" && ! provided_has "plan:${name}"; then
    provided_mark "plan:${name}"
    printf '%s\n' "${name}"
  fi
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
    fetch_url "${url%/}/index.json" "${CACHE_INDEX}.tmp"
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
          | select(((.commands // []) | length) > 0 or (.migration_stage // "") != "stage-1-auzix-native-repack")
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
      long|describe|descriptions)
        "${JQ}" -r --slurpfile state "${INSTALLED}" '
          .packages[]
          | . as $package
          | [
              $package.name,
              $package.version,
              $package.kind,
              (if any($state[0].installed[]; .name == $package.name) then "installed" else "available" end),
              (((.size // 0) / 1048576 * 10 | floor) / 10 | tostring) + " MiB",
              ((.description // .migration_stage // "") | gsub("[\t\r\n]+"; " "))
            ]
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
  status)
    require_index
    [ "$#" -eq 1 ] || die "status requires a package name"
    package_json="$(package_query "$1")"
    installed_json="$(installed_query "$1")"
    [ -n "${package_json}" ] || package_json='{}'
    [ -n "${installed_json}" ] || installed_json='{}'
    "${JQ}" -n --arg name "$1" --argjson available "${package_json}" --argjson installed "${installed_json}" '
      {
        name: ($available.name // $installed.name // $name),
        state: (if ($installed | length) > 0 then "installed" elif ($available | length) > 0 then "available" else "missing" end),
        installed: $installed,
        available: $available
      }
    '
    ;;
  files)
    require_index
    [ "$#" -eq 1 ] || die "files requires a package name"
    package_json="$(package_query "$1")"
    [ -n "${package_json}" ] || die "package not found: $1"
    package_file_list "${package_json}" | "${BB}" sort -u
    ;;
  owner)
    require_index
    [ "$#" -eq 1 ] || die "owner requires a path"
    query_path="$1"
    found=0
    "${JQ}" -c '.packages[]' "${CACHE_INDEX}" |
      while IFS= read -r package_json; do
        if package_file_list "${package_json}" | "${BB}" grep -Fx -- "${query_path}" >/dev/null 2>&1; then
          printf '%s\n' "${package_json}" | "${JQ}" -r '[.name, .version, .kind, .prefix // ""] | @tsv'
          found=1
        fi
      done
    ;;
  env)
    require_index
    [ "$#" -eq 1 ] || die "env requires a package name"
    package_json="$(package_query "$1")"
    [ -n "${package_json}" ] || die "package not found: $1"
    package_runtime_env "${package_json}"
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
  bootstrap-manifest)
    require_index
    [ "$#" -eq 1 ] || die "bootstrap-manifest requires a package list file"
    [ -s "$1" ] || die "bootstrap manifest is missing or empty: $1"
    seed_provided_state
    count=0
    missing=0
    while IFS= read -r manifest_line || [ -n "${manifest_line}" ]; do
      manifest_line="${manifest_line%%#*}"
      manifest_line="$(printf '%s' "${manifest_line}" | "${BB}" sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -n "${manifest_line}" ] || continue
      case "${manifest_line}" in \[*\]) continue ;; esac
      if record_installed_name "${manifest_line}" "bootstrap-manifest:$1"; then
        count=$((count + 1))
      else
        echo "bootstrap-manifest missing package: ${manifest_line}" >&2
        missing=$((missing + 1))
      fi
    done <"$1"
    echo "Bootstrapped manifest records=${count} missing=${missing} installed_total=$("${JQ}" '.installed | length' "${INSTALLED}")"
    ;;
  bootstrap-runtime-substrate)
    seed_provided_state
    count=0
    for base_name in Libc6 LibgccS1 GCC14Base; do
      if record_base_runtime_provider "${base_name}"; then
        count=$((count + 1))
      fi
    done
    echo "Bootstrapped runtime substrate records=${count} installed_total=$("${JQ}" '.installed | length' "${INSTALLED}")"
    ;;
  bootstrap-receipts)
    receipt_dir="${1:-/System/PackageDB}"
    [ -d "${receipt_dir}" ] || die "receipt directory missing: ${receipt_dir}"
    count=0
    failed=0
    for receipt in "${receipt_dir}"/*.auzix.json "${receipt_dir}"/*.json; do
      [ -s "${receipt}" ] || continue
      if record_receipt_file "${receipt}" "bootstrap-receipts:${receipt_dir}"; then
        count=$((count + 1))
      else
        echo "bootstrap-receipts failed receipt: ${receipt}" >&2
        failed=$((failed + 1))
      fi
    done
    seed_provided_state
    echo "Bootstrapped receipts records=${count} failed=${failed} installed_total=$("${JQ}" '.installed | length' "${INSTALLED}")"
    ;;
  plan)
    require_index
    [ "$#" -eq 1 ] || die "plan requires a package name"
    seed_provided_state
    plan_file="${WORK}/plan.$$.names"
    plan_one "$1" "" | "${BB}" tee "${plan_file}" >/dev/null
    fail_if_blocked
    echo "PLAN package=$1 new_packages=$("${BB}" wc -l <"${plan_file}")"
    cat "${plan_file}"
    ;;
  install)
    require_index
    [ "$#" -eq 1 ] || die "install requires a package name"
    seed_provided_state
    plan_one "$1" "" >/dev/null
    fail_if_blocked
    reset_transaction_marks
    seed_provided_state
    install_one "$1" ""
    fail_if_blocked
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
sed -i "s|@AUZIX_DEFAULT_REPO@|${DEFAULT_REPO}|g" "${PROGRAM_ROOT}/Commands/auzix-pkg"
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
