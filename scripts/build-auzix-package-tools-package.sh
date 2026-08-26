#!/usr/bin/env bash
set -euo pipefail

# AUZiX SCRIPT CONTRACT
# Purpose:
#   Build the AUZiX package-management program payload and emit the `auzix-pkg`
#   transaction client used by live media, installed roots, and validation
#   containers.
# Inputs:
#   AUZiX root path argument; repository URL via AUZIX_DEFAULT_REPO; host jq/ldd.
# Outputs:
#   /Programs/AuzixPackageTools/<version>, compatibility command exports, package
#   DB receipt, and default repository config inside the target AUZiX root.
# May modify:
#   Only the supplied target root during build time. The generated `auzix-pkg`
#   may install package payloads during explicit package transactions.
# Must not modify:
#   The host OS; active AUZiX runtime substrate during normal leaf transactions;
#   root compatibility aliases except through explicit installer/base lanes.
# Idempotency:
#   Rebuilding this package replaces only its versioned payload and declared
#   command exports. Runtime package transactions must be idempotent no-ops when
#   the requested version/checksum is already installed.
# Failure behavior:
#   Fail closed on unsupported repo metadata, protected runtime/archive paths,
#   dependency planning blockers, unsafe archive paths, and conflicting package
#   state. Do not silently force-link or normalize a live root.
# Known-good reference:
#   notes/auzix-small-moon-live-smoke-2026-08-22.md
# Validation receipt:
#   Container transaction proof: refresh, bootstrap receipts/runtime, plan, pull,
#   install, repeat install, protected runtime hash comparison.

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
      case "$(basename "${dep}")" in
        ld-linux-x86-64.so.2|libc.so.6|libm.so.6|libpthread.so.0|libdl.so.2)
          # Core ABI belongs to /System/Libraries.  Do not create a private
          # glibc pocket inside AuzixPackageTools; mixing loaders/libc copies
          # is exactly how we get private-symbol and stale-runtime failures.
          install -D -m 0755 "${dep}" "${AUZIX_ROOT}/System/Libraries/Runtime/glibc/$(basename "${dep}")"
          continue
          ;;
      esac
      case "${dep}" in
        /lib64/*)
          install -D -m 0755 "${dep}" "${RUNTIME_LIB64}/$(basename "${dep}")"
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
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
exec /System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2 \
  --library-path /System/Libraries:/System/Libraries/Runtime/glibc:/Programs/AuzixPackageTools/current/Libraries \
  /Programs/AuzixPackageTools/current/Commands/jq.real "$@"
SCRIPT
chmod 0755 "${PROGRAM_ROOT}/Commands/jq"

cat > "${PROGRAM_ROOT}/Commands/auzix-pkg" <<'SCRIPT'
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -eu

# AUZIX INVARIANT:
# This client owns package transaction state, not rootfs design. Normal leaf
# installs must not mutate the active runtime substrate, root compatibility
# aliases, or existing protected paths. If that behavior is required, stop and
# run an installer/base transaction with explicit opt-in.

PATH=/Programs/AuzixPackageTools/current/Commands:/System/Compatibility/bin:/Programs/BusyBox/1.36.1/Commands
export PATH
BB=/Programs/BusyBox/1.36.1/Commands/busybox
JQ=/Programs/AuzixPackageTools/current/Commands/jq
SETTINGS=/System/Settings/packages
STATE=/System/State/packages
LOGS=/System/Logs/packages
REPO_CONF="${SETTINGS}/repositories.conf"
CACHE_INDEX="${STATE}/repo-index.json"
LOOKUP_DIR="${STATE}/by-name"
INSTALLED="${STATE}/installed.json"
WORK=/Work/Temp/auzix-pkg
CACHE="${WORK}/archives"
PROVIDED="${WORK}/provided.names"
PLAN_VISITING="${WORK}/plan.visiting.names"
PLAN_OUTPUT="${WORK}/plan.output.names"
PREFETCHED="${WORK}/prefetch.seen.names"
BLOCKED="${WORK}/transaction.blocked"
LOCK_DIR="${WORK}/transaction.lock"

usage() {
  cat <<'USAGE'
Usage:
  auzix-pkg refresh [REPOSITORY_URL]
  auzix-pkg refresh-ldcache
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
  auzix-pkg pull PACKAGE
  auzix-pkg install PACKAGE
  auzix-pkg update PACKAGE
  auzix-pkg install-one PACKAGE

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
  "${BB}" mkdir -p "${SETTINGS}" "${STATE}" "${LOGS}" "${WORK}" "${CACHE}"
  if [ ! -s "${REPO_CONF}" ]; then
    echo "@AUZIX_DEFAULT_REPO@" >"${REPO_CONF}"
  fi
  if [ ! -s "${INSTALLED}" ]; then
    "${BB}" tee "${INSTALLED}" >/dev/null <<'JSON'
{"format":"auzix-installed-v1","installed":[]}
JSON
  fi
  : >"${PROVIDED}"
  : >"${PLAN_VISITING}"
  : >"${PLAN_OUTPUT}"
  : >"${PREFETCHED}"
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
  prepare_package_lookup
  key="$(package_lookup_key "${package_name}")"
  if [ -s "${LOOKUP_DIR}/${key}.json" ]; then
    "${BB}" cat "${LOOKUP_DIR}/${key}.json"
    return 0
  fi
  return 0
}

package_lookup_key() {
  printf '%s\n' "$1" |
    "${BB}" tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz' |
    "${BB}" sed 's/[^a-z0-9_.+-]/_/g'
}

prepare_package_lookup() {
  [ -s "${CACHE_INDEX}" ] || return 1
  stamp="${LOOKUP_DIR}/.repo-index.stamp"
  # The repository index is replaced only by `refresh`, which invalidates this
  # directory below.  Re-hashing a multi-megabyte index for every node in a
  # dependency plan turns an O(n) traversal into gigabytes of redundant I/O.
  if [ -s "${stamp}" ]; then
    return 0
  fi

  current_stamp="$("${BB}" wc -c <"${CACHE_INDEX}" 2>/dev/null || echo 0):$("${BB}" sha256sum "${CACHE_INDEX}" 2>/dev/null | "${BB}" awk '{print $1}')"

  tmp_dir="${LOOKUP_DIR}.tmp.$$"
  "${BB}" rm -rf "${tmp_dir}"
  "${BB}" mkdir -p "${tmp_dir}"
  "${JQ}" -r '
    .packages[]
    | [(.name | ascii_downcase | gsub("[^a-z0-9_.+-]"; "_")), (. | tojson | @base64)]
    | @tsv
  ' "${CACHE_INDEX}" |
    while IFS="$(printf '\t')" read -r key package_base64 || [ -n "${key}" ]; do
      [ -n "${key}" ] || continue
      printf '%s' "${package_base64}" |
        "${BB}" base64 -d >"${tmp_dir}/${key}.json" ||
        die "failed to decode repository lookup record: ${key}"
    done
  echo "${current_stamp}" >"${tmp_dir}/.repo-index.stamp"
  "${BB}" rm -rf "${LOOKUP_DIR}"
  "${BB}" mv "${tmp_dir}" "${LOOKUP_DIR}"
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

compatibility_exports_present_by_name() {
  package_name="$1"
  package_json="$(package_query "${package_name}" || true)"
  [ -n "${package_json}" ] || return 1
  exports_file="${WORK}/compat-exports.$$.txt"
  printf '%s\n' "${package_json}" |
    "${JQ}" -r '.compatibility_exports[]? // empty' >"${exports_file}"
  [ -s "${exports_file}" ] || {
    "${BB}" rm -f "${exports_file}"
    return 1
  }
  while IFS= read -r export_path || [ -n "${export_path}" ]; do
    [ -n "${export_path}" ] || continue
    if [ ! -e "${export_path}" ] && [ ! -L "${export_path}" ]; then
      "${BB}" rm -f "${exports_file}"
      return 1
    fi
  done <"${exports_file}"
  "${BB}" rm -f "${exports_file}"
  return 0
}

program_present_by_name() {
  package_name="$1"
  [ -e "/Programs/${package_name}/current" ] || [ -d "/Programs/${package_name}" ]
}

active_glibc_version() {
  [ -x /System/Libraries/Runtime/glibc/libc.so.6 ] || return 1
  /System/Libraries/Runtime/glibc/libc.so.6 2>&1 |
    "${BB}" awk '''/release version/ { value=$NF; found=1 } /GNU C Library/ && !found { for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+[.][0-9]+/) { value=$i; found=1; break } } END { gsub(/[^0-9.].*$/, "", value); sub(/[.]$/, "", value); if (found) print value; exit found ? 0 : 1 }'''
}

version_gt() {
  left="$1"
  right="$2"
  [ "${left}" != "${right}" ] &&
    [ "$(printf '%s\n%s\n' "${left}" "${right}" | "${BB}" sort -V | "${BB}" tail -n 1)" = "${left}" ]
}

assert_plan_runtime_compatible() {
  plan_file="$1"
  active_glibc="$(active_glibc_version 2>/dev/null || true)"
  [ -n "${active_glibc}" ] || die "cannot determine active AUZiX core glibc version"
  while IFS= read -r plan_name || [ -n "${plan_name}" ]; do
    [ -n "${plan_name}" ] || continue
    plan_package_json="$(package_query "${plan_name}" || true)"
    [ -n "${plan_package_json}" ] || continue
    required_glibc="$(printf '%s\n' "${plan_package_json}" | "${JQ}" -r '.source.required_glibc // empty')"
    [ -n "${required_glibc}" ] || continue
    required_glibc="${required_glibc#GLIBC_}"
    if version_gt "${required_glibc}" "${active_glibc}"; then
      die "runtime-rebuild-required: ${plan_name} needs glibc ${required_glibc}, active AUZiX core is ${active_glibc}; rebuild the base release, do not install a second glibc"
    fi
  done <"${plan_file}"
}

base_runtime_provides() {
  package_name="$1"
  case "${package_name}" in
    Libc6|LibgccS1|GCC14Base)
      [ -x /System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2 ] &&
      [ -x /System/Libraries/Runtime/glibc/libc.so.6 ]
      ;;
    Libstdc6)
      [ -e /System/Libraries/libstdc++.so.6 ] ||
      [ -e /System/Compatibility/usr/lib/x86_64-linux-gnu/libstdc++.so.6 ] ||
      [ -e /System/Compatibility/lib/x86_64-linux-gnu/libstdc++.so.6 ]
      ;;
    Libatomic1)
      [ -e /System/Libraries/libatomic.so.1 ] ||
      [ -e /System/Compatibility/usr/lib/x86_64-linux-gnu/libatomic.so.1 ] ||
      [ -e /System/Compatibility/lib/x86_64-linux-gnu/libatomic.so.1 ]
      ;;
    Zlib1g)
      [ -e /System/Libraries/libz.so.1 ] ||
      [ -e /System/Compatibility/usr/lib/x86_64-linux-gnu/libz.so.1 ] ||
      [ -e /System/Compatibility/lib/x86_64-linux-gnu/libz.so.1 ]
      ;;
    *) return 1 ;;
  esac
}

core_runtime_package() {
  package_name="$1"
  case "${package_name}" in
    Libc6|LibgccS1|GCC14Base|Libstdc6|Libatomic1|Zlib1g) return 0 ;;
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
    Libc6|LibgccS1|GCC14Base|BusyBox|DBus|PAM|Polkit|Udev|Systemd|Xorg|XorgServer|Xserver*|EFL|Enlightenment|Terminology)
      return 0
      ;;
    *) return 1 ;;
  esac
}

substrate_install_allowed() {
  [ "${AUZIX_ALLOW_SUBSTRATE_INSTALL:-0}" = "1" ] ||
  [ "${AUZIX_PULL_ONLY:-0}" = "1" ]
}

substrate_present() {
  package_name="$1"
  core_runtime_dependency_satisfied "${package_name}" ||
  provided_has "${package_name}" ||
  is_installed "${package_name}" ||
  receipt_installed_by_name "${package_name}" ||
  program_present_by_name "${package_name}"
}

guard_substrate_install() {
  package_name="$1"
  reason="${2:-dependency}"
  substrate_package "${package_name}" || return 0
  substrate_install_allowed && return 0

  if substrate_present "${package_name}"; then
    provided_mark "${package_name}"
    return 1
  fi

  mark_runtime_block "protected substrate package ${package_name} is required by ${reason}, but live leaf installs may not mutate the active AUZiX substrate. Rebuild/install through the base lane or set AUZIX_ALLOW_SUBSTRATE_INSTALL=1 for installer/base transactions."
  return 2
}

record_base_runtime_provider() {
  package_name="$1"
  base_runtime_provides "${package_name}" || return 1
  version="base-runtime"
  case "${package_name}" in
    Libc6) version="$(active_glibc_version 2>/dev/null || echo base-runtime)"; record_name="ActiveBaseRuntimeLibc6" ;;
    LibgccS1) version="$(active_glibc_version 2>/dev/null || echo base-runtime)-glibc-stratum"; record_name="ActiveBaseRuntimeLibgcc" ;;
    GCC14Base) version="$(active_glibc_version 2>/dev/null || echo base-runtime)-glibc-stratum"; record_name="ActiveBaseRuntimeGCC" ;;
    Libstdc6) version="$(active_glibc_version 2>/dev/null || echo base-runtime)-glibc-stratum"; record_name="ActiveBaseRuntimeLibstdc" ;;
    Libatomic1) version="$(active_glibc_version 2>/dev/null || echo base-runtime)-glibc-stratum"; record_name="ActiveBaseRuntimeLibatomic" ;;
    Zlib1g) version="$(active_glibc_version 2>/dev/null || echo base-runtime)-glibc-stratum"; record_name="ActiveBaseRuntimeZlib" ;;
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
  : >"${PLAN_VISITING}"
  : >"${PLAN_OUTPUT}"
  : >"${PREFETCHED}"
  : >"${BLOCKED}"
}

provided_mark() {
  provided_name="$1"
  [ -n "${provided_name}" ] || return 0
  provided_has "${provided_name}" || echo "${provided_name}" >>"${PROVIDED}"
}

plan_seen_has() {
  "${BB}" grep -Fxq "$1" "${PLAN_VISITING}" 2>/dev/null
}

plan_seen_mark() {
  plan_name="$1"
  [ -n "${plan_name}" ] || return 0
  plan_seen_has "${plan_name}" || echo "${plan_name}" >>"${PLAN_VISITING}"
}

plan_output_has() {
  "${BB}" grep -Fxq "$1" "${PLAN_OUTPUT}" 2>/dev/null
}

plan_output_mark() {
  plan_name="$1"
  [ -n "${plan_name}" ] || return 0
  plan_output_has "${plan_name}" || echo "${plan_name}" >>"${PLAN_OUTPUT}"
}

prefetch_seen_has() {
  "${BB}" grep -Fxq "$1" "${PREFETCHED}" 2>/dev/null
}

prefetch_seen_mark() {
  prefetch_name="$1"
  [ -n "${prefetch_name}" ] || return 0
  prefetch_seen_has "${prefetch_name}" || echo "${prefetch_name}" >>"${PREFETCHED}"
}

mark_runtime_block() {
  blocked_message="$1"
  printf '%s\n' "${blocked_message}" >>"${BLOCKED}"
}

release_transaction_lock() {
  if [ "${AUZIX_LOCK_HELD:-0}" = "1" ]; then
    "${BB}" rm -f "${LOCK_DIR}/owner" 2>/dev/null || true
    "${BB}" rmdir "${LOCK_DIR}" 2>/dev/null || true
    AUZIX_LOCK_HELD=0
  fi
}

acquire_transaction_lock() {
  action="$1"
  if [ -d "${LOCK_DIR}" ] && [ -s "${LOCK_DIR}/owner" ]; then
    lock_pid="$("${BB}" sed -n 's/.* pid=\([0-9][0-9]*\).*/\1/p' "${LOCK_DIR}/owner" 2>/dev/null || true)"
    if [ -n "${lock_pid}" ] && ! "${BB}" kill -0 "${lock_pid}" 2>/dev/null; then
      echo "auzix-pkg: reclaiming stale transaction lock from pid ${lock_pid}" >&2
      "${BB}" rm -f "${LOCK_DIR}/owner" 2>/dev/null || true
      "${BB}" rmdir "${LOCK_DIR}" 2>/dev/null || true
    fi
  fi
  if "${BB}" mkdir "${LOCK_DIR}" 2>/dev/null; then
    AUZIX_LOCK_HELD=1
    trap release_transaction_lock EXIT INT TERM
    echo "${action} pid=$$ started=$("${BB}" date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || "${BB}" date)" >"${LOCK_DIR}/owner"
    return 0
  fi
  echo "auzix-pkg: another package transaction is active:" >&2
  "${BB}" cat "${LOCK_DIR}/owner" >&2 2>/dev/null || true
  echo "auzix-pkg: if this is stale, remove ${LOCK_DIR}" >&2
  exit 75
}

fail_if_blocked() {
  if [ -s "${BLOCKED}" ]; then
    first_block="$("${BB}" head -n 1 "${BLOCKED}")"
    die "${first_block}"
  fi
}

dedupe_plan_file() {
  plan_file="$1"
  tmp_plan="${plan_file}.unique.$$"
  "${BB}" awk 'NF && !seen[$0]++ { print }' "${plan_file}" >"${tmp_plan}"
  "${BB}" mv "${tmp_plan}" "${plan_file}"
}

write_provided_json() {
  provided_json="$1"
  "${BB}" sort -fu "${PROVIDED}" 2>/dev/null |
    "${JQ}" -Rsc 'split("\n") | map(select(length > 0) | ascii_downcase)' >"${provided_json}"
}

resolve_plan_json() {
  requested="$1"
  names_file="$2"
  json_file="$3"
  seed_provided_state
  provided_json="${WORK}/provided.$$.json"
  candidate_file="${WORK}/plan-candidates.$$.names"
  write_provided_json "${provided_json}"
  # Older receipts flattened the full dependency closure into `depends`, which
  # is discovery order rather than install order.  Reversing that list is not a
  # topological sort.  Recover each Debian package's direct edges from the
  # preserved control Depends field, map Debian names to their AUZiX names, and
  # emit a dependency-first DFS order.  New receipts also carry direct_depends.
  "${JQ}" -r --arg requested "${requested}" --slurpfile provided "${provided_json}" '
    def key: ascii_downcase;
    def debkey:
      gsub("\\([^)]*\\)"; "")
      | gsub("\\[[^]]*\\]"; "")
      | gsub("<[^>]*>"; "")
      | gsub("^[[:space:]]+|[[:space:]]+$"; "")
      | split(":")[0]
      | ascii_downcase;
    (reduce .packages[] as $p ({}; .[($p.name | key)] = $p)) as $packages
    | (reduce .packages[] as $p ({};
        if (($p.source.package // "") | length) > 0
        then .[($p.source.package | ascii_downcase)] = $p.name
        else . end
      )) as $debian_to_auzix
    | (($provided[0] // []) | reduce .[] as $name ({}; .[$name] = true)) as $provided_map
    | def direct($p):
        if (($p.direct_depends // []) | length) > 0 then $p.direct_depends
        elif (($p.source.upstream_depends // "") | length) > 0 then
          [
            $p.source.upstream_depends
            | split(",")[]
            | [split("|")[] | debkey | select($debian_to_auzix[.] != null) | $debian_to_auzix[.]]
            | first
            | select(. != null)
          ]
          | unique
        else ($p.depends // [])
        end;
      def visit($name; $state):
        ($name | key) as $k
        | if ($state.done[$k] // false) then $state
          elif ($state.visiting[$k] // false) then $state
          elif $packages[$k] == null then error("dependency not found in repository: " + $name)
          else
            reduce (direct($packages[$k])[]) as $dependency
              ($state | .visiting[$k] = true; visit($dependency; .))
            | .visiting[$k] = false
            | .done[$k] = true
            | if ($provided_map[$k] // false) then .
              else .out += [$packages[$k].name]
              end
          end;
      visit($requested; {done: {}, visiting: {}, out: []})
      | .out[]
  ' "${CACHE_INDEX}" >"${candidate_file}"

  # seed_provided_state already captured live receipts, /Programs, compatibility
  # exports, and runtime providers before the jq pass.  Do not rerun a full jq
  # installed-state query for every candidate: that recreates the old O(n^2)
  # planner.  The cheap provided lookup is sufficient here; protected nodes get
  # one explicit live guard before a transaction starts.
  : >"${names_file}"
  while IFS= read -r candidate || [ -n "${candidate}" ]; do
    [ -n "${candidate}" ] || continue
    if provided_has "${candidate}"; then
      provided_mark "${candidate}"
      continue
    fi
    if substrate_package "${candidate}"; then
      if guard_substrate_install "${candidate}" "plan:${requested}"; then
        :
      else
        guard_rc=$?
        [ "${guard_rc}" = "1" ] && continue
        continue
      fi
    fi
    printf '%s\n' "${candidate}" >>"${names_file}"
  done <"${candidate_file}"
  fail_if_blocked
  dedupe_plan_file "${names_file}"
  "${JQ}" --rawfile names "${names_file}" '
    ($names | split("\n") | map(select(length > 0) | ascii_downcase)) as $wanted
    | [.packages[] | select((.name | ascii_downcase) as $name | $wanted | index($name))]
  ' "${CACHE_INDEX}" >"${json_file}"
  "${BB}" rm -f "${provided_json}" "${candidate_file}"
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
      [ -e "${program_dir}/current" ] || continue
      provided_mark "${program_dir##*/}"
    done
  fi
  for base_name in Libc6 LibgccS1 GCC14Base Libstdc6 Libatomic1 Zlib1g; do
    if base_runtime_provides "${base_name}"; then
      record_base_runtime_provider "${base_name}" >/dev/null 2>&1 || provided_mark "${base_name}"
    fi
  done
}

dependency_satisfied() {
  package_name="$1"
  provided_has "${package_name}" ||
  substrate_present "${package_name}" ||
  receipt_installed_by_name "${package_name}" ||
  program_present_by_name "${package_name}" ||
  compatibility_exports_present_by_name "${package_name}"
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
  installed_name="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.name // empty')"
  [ -n "${installed_name}" ] && provided_mark "${installed_name}"
  printf '%s\n' "${package_json}" | "${JQ}" -r '.provides[]? // empty' 2>/dev/null |
    while IFS= read -r provided_name; do
      [ -n "${provided_name}" ] && provided_mark "${provided_name}"
    done
}

validate_archive() {
  archive="$1"
  "${BB}" tar -tzf "${archive}" |
    "${BB}" awk '
      /^\// { bad=1 }
      /(^|\/)\.\.(\/|$)/ { bad=1 }
      END { exit bad }
    ' || die "unsafe path found in ${archive}"
  if [ "${AUZIX_PULL_ONLY:-0}" != "1" ] && ! substrate_install_allowed; then
    blocked_paths="${WORK}/protected-archive-paths.$$.txt"
    : >"${blocked_paths}"
    "${BB}" tar -tzf "${archive}" |
      while IFS= read -r archive_path; do
        # GNU/BusyBox tar commonly prefix members with "./".  Normalize that
        # before comparing protected paths or the guard silently misses them.
        path="${archive_path#./}"
        path="${path%/}"
        [ -n "${path}" ] || continue
        case "${path}" in
          bin|sbin|lib|lib64|usr|etc|var|root|opt)
            if [ -e "/${path}" ] || [ -L "/${path}" ]; then
              printf '%s\n' "${path}" >>"${blocked_paths}"
            fi
            ;;
        System/Libraries|System/Libraries/*|\
        System/Compatibility/bin/*|System/Compatibility/sbin/*|\
        System/Settings/ld.so.conf|System/Settings/ld.so.conf.d|System/Settings/ld.so.conf.d/*|System/Settings/ld.so.cache)
          if [ -e "/${path}" ] || [ -L "/${path}" ]; then
            printf '%s\n' "${path}" >>"${blocked_paths}"
          fi
          ;;
        esac
      done
    if [ -s "${blocked_paths}" ]; then
      first_blocked="$("${BB}" head -n 1 "${blocked_paths}")"
      die "archive ${archive} would replace existing protected path ${first_blocked}; rerun only from installer/base lane with AUZIX_ALLOW_SUBSTRATE_INSTALL=1"
    fi
    "${BB}" rm -f "${WORK}/protected-archive-paths.$$.txt"
  fi
}

protected_archive_conflict() {
  archive="$1"
  conflicts_file="${WORK}/protected-archive-conflicts.$$.txt"
  : >"${conflicts_file}"
  "${BB}" tar -tzf "${archive}" |
    while IFS= read -r archive_path; do
      path="${archive_path%/}"
      [ -n "${path}" ] || continue
      case "${path}" in
        bin|sbin|lib|lib64|usr|etc|var|root|opt)
          if [ -e "/${path}" ] || [ -L "/${path}" ]; then
            printf '%s\n' "${path}" >>"${conflicts_file}"
          fi
          ;;
        System/Libraries|System/Libraries/*|\
        System/Compatibility/lib|System/Compatibility/lib/*|\
        System/Compatibility/lib64|System/Compatibility/lib64/*|\
        System/Compatibility/usr/lib|System/Compatibility/usr/lib/*|\
        System/Compatibility/bin/*|System/Compatibility/sbin/*|\
        System/Settings/ld.so.conf|System/Settings/ld.so.conf.d|System/Settings/ld.so.conf.d/*|System/Settings/ld.so.cache)
          if [ -e "/${path}" ] || [ -L "/${path}" ]; then
            printf '%s\n' "${path}" >>"${conflicts_file}"
          fi
          ;;
      esac
    done
  if [ -s "${conflicts_file}" ]; then
    "${BB}" head -n 1 "${conflicts_file}"
    "${BB}" rm -f "${conflicts_file}"
    return 0
  fi
  "${BB}" rm -f "${conflicts_file}"
  return 1
}

refresh_runtime_linker() {
  ldconfig_path=""
  ld_conf=/System/Settings/ld.so.conf
  ld_conf_dir=/System/Settings/ld.so.conf.d
  auzix_ld_conf="${ld_conf_dir}/auzix-runtime.conf"
  ld_cache=/System/Settings/ld.so.cache

  # AUZIX LINKER CONTRACT:
  # Debian packages commonly finish library installs by refreshing ldconfig.
  # AUZiX must do the same, but from the active runtime substrate only. Do not
  # teach the global loader cache about arbitrary leaf package RootFS trees; leaf
  # packages use their wrappers/runtime ladder for package-local libraries.
  "${BB}" mkdir -p "${ld_conf_dir}" /System/Settings /System/State/ldconfig 2>/dev/null || true
  {
    echo "# AUZiX runtime linker configuration."
    echo "# Generated by auzix-pkg; package-local /Programs trees stay out of the global cache."
    echo "include /System/Settings/ld.so.conf.d/*.conf"
  } >"${ld_conf}.tmp.$$" 2>/dev/null || true
  if [ -s "${ld_conf}.tmp.$$" ]; then
    "${BB}" mv "${ld_conf}.tmp.$$" "${ld_conf}" 2>/dev/null || true
  else
    "${BB}" rm -f "${ld_conf}.tmp.$$" 2>/dev/null || true
  fi
  : >"${auzix_ld_conf}.tmp.$$" 2>/dev/null || true
  for runtime_dir in \
    /System/Libraries \
    /System/Libraries/Runtime/glibc \
    /System/Compatibility/lib \
    /System/Compatibility/lib64 \
    /System/Compatibility/lib/x86_64-linux-gnu \
    /System/Compatibility/usr/lib \
    /System/Compatibility/usr/lib/x86_64-linux-gnu; do
    [ -d "${runtime_dir}" ] || continue
    printf '%s\n' "${runtime_dir}" >>"${auzix_ld_conf}.tmp.$$" 2>/dev/null || true
  done
  if [ -s "${auzix_ld_conf}.tmp.$$" ]; then
    "${BB}" mv "${auzix_ld_conf}.tmp.$$" "${auzix_ld_conf}" 2>/dev/null || true
  else
    "${BB}" rm -f "${auzix_ld_conf}.tmp.$$" 2>/dev/null || true
  fi

  for candidate in \
    /System/Compatibility/sbin/ldconfig \
    /System/Compatibility/usr/sbin/ldconfig \
    /Programs/Libc6/current/RootFS/sbin/ldconfig \
    /Programs/Libc6/current/RootFS/usr/sbin/ldconfig \
    /sbin/ldconfig \
    /usr/sbin/ldconfig; do
    if [ -x "${candidate}" ]; then
      ldconfig_path="${candidate}"
      break
    fi
  done
  if [ -n "${ldconfig_path}" ]; then
    if [ -s "${ld_conf}" ]; then
      "${ldconfig_path}" -f "${ld_conf}" -C "${ld_cache}" >/dev/null 2>&1 ||
        "${ldconfig_path}" >/dev/null 2>&1 ||
        echo "ldconfig refresh failed: ${ldconfig_path}" >&2
    else
      "${ldconfig_path}" >/dev/null 2>&1 || echo "ldconfig refresh failed: ${ldconfig_path}" >&2
    fi
  elif substrate_install_allowed; then
    echo "ldconfig refresh skipped: no ldconfig command found in AUZiX runtime" >&2
  fi
}

archive_path_for_package() {
  package_json="$1"
  archive_name="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.package')"
  printf '%s/%s\n' "${CACHE}" "${archive_name}"
}

fetch_package_archive() {
  package_json="$1"
  name="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.name')"
  if prefetch_seen_has "${name}"; then
    echo "Prefetch already planned ${name}"
    return 0
  fi
  prefetch_seen_mark "${name}"
  base_url="$(repo_url)"
  archive_name="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.package')"
  expected_sha="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.sha256')"
  archive="$(archive_path_for_package "${package_json}")"
  source_url="${base_url%/}/packages/${archive_name}"

  if [ -s "${archive}" ]; then
    actual_sha="$("${BB}" sha256sum "${archive}" | "${BB}" awk '{print $1}')"
    if [ "${actual_sha}" = "${expected_sha}" ]; then
      echo "Cached ${name} ${archive_name}"
      validate_archive "${archive}"
      return 0
    fi
    "${BB}" rm -f "${archive}"
  fi

  echo "Prefetch ${name} ${source_url}"
  fetch_url "${source_url}" "${archive}.part"
  "${BB}" mv "${archive}.part" "${archive}"
  actual_sha="$("${BB}" sha256sum "${archive}" | "${BB}" awk '{print $1}')"
  [ "${actual_sha}" = "${expected_sha}" ] ||
    die "checksum mismatch for ${archive_name}: expected ${expected_sha}, got ${actual_sha}"
  validate_archive "${archive}"
}

prefetch_plan_file() {
  plan_file="$1"
  requested="$2"
  if [ -s "${plan_file}" ]; then
    while IFS= read -r plan_name || [ -n "${plan_name}" ]; do
      [ -n "${plan_name}" ] || continue
      package_json="$(package_query "${plan_name}")"
      [ -n "${package_json}" ] || die "planned package not found in repository: ${plan_name}"
      fetch_package_archive "${package_json}"
    done <"${plan_file}"
  fi
  if ! dependency_satisfied "${requested}"; then
    package_json="$(package_query "${requested}")"
    [ -n "${package_json}" ] || die "package not found in repository: ${requested}"
    fetch_package_archive "${package_json}"
  fi
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

package_has_desktop_surface() {
  package_json="$1"
  archive="$2"
  desktop_count="$(printf '%s\n' "${package_json}" | "${JQ}" -r '(.desktop_entries // []) | length' 2>/dev/null || echo 0)"
  [ "${desktop_count}" != "0" ] && return 0
  "${BB}" tar -tzf "${archive}" 2>/dev/null |
    "${BB}" grep -Eq '(^|/)(share/applications/.*[.]desktop|share/icons/|share/pixmaps/|share/mime/|glib-2[.]0/schemas/)' &&
    return 0
  return 1
}

refresh_desktop_surface() {
  package_json="$1"
  archive="$2"
  package_has_desktop_surface "${package_json}" "${archive}" || return 0

  echo "Refreshing desktop/menu surface"
  if [ -x /Programs/AuzixDesktopIntegration/current/Commands/activate ]; then
    /Programs/AuzixDesktopIntegration/current/Commands/activate || true
  fi
  if [ -x /System/Tools/repair-auzix-desktop-menu ]; then
    /System/Tools/repair-auzix-desktop-menu / || true
  fi
  if command -v update-desktop-database >/dev/null 2>&1 &&
     [ -d /System/Compatibility/usr/share/applications ]; then
    update-desktop-database /System/Compatibility/usr/share/applications >/dev/null 2>&1 || true
  elif [ -x /Programs/DesktopFileUtils/current/Commands/update-desktop-database ] &&
       [ -d /System/Compatibility/usr/share/applications ]; then
    /Programs/DesktopFileUtils/current/Commands/update-desktop-database \
      /System/Compatibility/usr/share/applications >/dev/null 2>&1 || true
  fi
  if [ -x /Programs/SharedMimeInfo/current/Commands/update-mime-database ] &&
     [ -d /System/Compatibility/usr/share/mime ]; then
    /Programs/SharedMimeInfo/current/Commands/update-mime-database \
      /System/Compatibility/usr/share/mime >/dev/null 2>&1 || true
  fi
  if command -v enlightenment_remote >/dev/null 2>&1 &&
     "${BB}" pidof enlightenment >/dev/null 2>&1; then
    # IDEMPOTENCY REQUIREMENT:
    # Do not use `su` here. Strict/live boots have repeatedly proven PAM/su is
    # not a safe early-session assumption, and invoking it from a package
    # transaction can turn a menu refresh into a session failure. Prefer the
    # static numeric handoff helper when present; otherwise leave a receipt and
    # let the session/user refresh menu caches later.
    if [ -x /System/Tools/auzix-run-as-uid ]; then
      /System/Tools/auzix-run-as-uid 1000 1000 /Users/auzix \
        /System/Compatibility/bin/sh -c \
        'DISPLAY=:0 HOME=/Users/auzix XDG_RUNTIME_DIR=/run/user/1000 enlightenment_remote -restart' \
        >/System/Logs/packages/enlightenment-menu-refresh.log 2>&1 || true
    else
      echo "desktop refresh deferred: /System/Tools/auzix-run-as-uid missing" \
        >/System/Logs/packages/enlightenment-menu-refresh.log
    fi
  fi
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
  if guard_substrate_install "${name}" "requested package ${requested}"; then
    :
  else
    guard_rc=$?
    if [ "${guard_rc}" = "1" ]; then
      echo "${name} is already provided by the active AUZiX substrate; not replacing it from a leaf transaction"
      return 0
    fi
    fail_if_blocked
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
        if guard_substrate_install "${dependency}" "${name}"; then
          :
        else
          guard_rc=$?
          if [ "${guard_rc}" = "1" ]; then
            echo "Dependency ${dependency} already satisfied by active AUZiX substrate; not reinstalling"
            continue
          fi
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
  archive="$(archive_path_for_package "${package_json}")"
  source_url="${base_url%/}/packages/${archive_name}"

  if [ ! -s "${archive}" ]; then
    fetch_package_archive "${package_json}"
  fi

  validate_archive "${archive}"
  if substrate_install_allowed; then
    "${BB}" tar -xzpf "${archive}" -C /
  else
    # Leaf packages keep libraries in their versioned /Programs RootFS.  Their
    # wrappers compose dependency paths explicitly; publishing global library
    # aliases during a live transaction can replace the libraries used by PID
    # 1, Xorg, or DBus.  Global promotion belongs to the installer/base lane.
    "${BB}" tar -xzpf "${archive}" -C / \
      --exclude='./System/Libraries/*' \
      --exclude='./System/Compatibility/lib/*' \
      --exclude='./System/Compatibility/lib64/*' \
      --exclude='./System/Compatibility/usr/lib/x86_64-linux-gnu/*'
  fi
  # Root finalization and the global linker cache belong to installer/base
  # transactions.  Running them for every leaf dependency republishes global
  # aliases and can mutate the live desktop underneath PID 1.
  if substrate_install_allowed; then
    refresh_runtime_linker
  fi
  if substrate_install_allowed && [ -x /System/Tools/finalize-installed-root ]; then
    AUZIX_LINK_MODE="${AUZIX_LINK_MODE:-strict}" /System/Tools/finalize-installed-root /
  fi
  run_post_install "${package_json}"
  if [ "${AUZIX_DEFER_DESKTOP_REFRESH:-0}" != "1" ]; then
    refresh_desktop_surface "${package_json}" "${archive}"
  fi
  if substrate_install_allowed; then
    refresh_runtime_linker
  fi
  record_install "${package_json}" "${base_url}"
  provided_mark "${name}"
  echo "Installed ${name} $(printf '%s\n' "${package_json}" | "${JQ}" -r '.version')"
}

install_plan_file() {
  plan_file="$1"
  requested="$2"
  if [ -s "${plan_file}" ]; then
    while IFS= read -r plan_name || [ -n "${plan_name}" ]; do
      [ -n "${plan_name}" ] || continue
      if dependency_satisfied "${plan_name}"; then
        echo "Plan package ${plan_name} already satisfied; not reinstalling"
        continue
      fi
      package_json="$(package_query "${plan_name}")"
      [ -n "${package_json}" ] || die "planned package not found in repository: ${plan_name}"
      archive="$(archive_path_for_package "${package_json}")"
      if [ "${plan_name}" != "${requested}" ] &&
         [ "${AUZIX_LEAF_RESCUE_SKIP_PROTECTED:-0}" = "1" ] &&
         [ "${AUZIX_ALLOW_SUBSTRATE_INSTALL:-0}" != "1" ] &&
         [ -s "${archive}" ]; then
        conflict_path="$(protected_archive_conflict "${archive}" || true)"
        if [ -n "${conflict_path}" ]; then
          # FAIL CLOSED:
          # Skipping a protected dependency and marking it provided is an
          # emergency demo/rescue hatch only. Public-beta proof must default to
          # failing the transaction so dependency state cannot lie about a
          # missing substrate component.
          echo "Plan package ${plan_name} conflicts with protected live path ${conflict_path}; skipping in leaf rescue transaction"
          provided_mark "${plan_name}"
          continue
        fi
      fi
      echo "INSTALL_STEP package=${plan_name}"
      AUZIX_SKIP_DEPS=1 install_one "${plan_name}" ""
      # install_one records the receipt and marks every newly provided name in
      # the live transaction state.  Re-scanning the complete installed set at
      # every dependency made this loop O(n^2) without changing its result.
    done <"${plan_file}"
  fi
  if ! dependency_satisfied "${requested}"; then
    echo "INSTALL_STEP package=${requested}"
    AUZIX_SKIP_DEPS=1 install_one "${requested}" ""
  fi
}

plan_one() {
  requested="$1"
  stack="${2:-}"
  package_is_satisfied=0
  if plan_seen_has "${requested}"; then
    [ "${AUZIX_PLAN_VERBOSE:-0}" = "1" ] && echo "Plan already seen ${requested}" >&2
    return 0
  fi
  if [ "${AUZIX_PLAN_VERBOSE:-0}" = "1" ]; then
    if [ -n "${stack}" ]; then
      echo "Planning dependency ${requested}" >&2
    else
      echo "Planning package ${requested}" >&2
    fi
  fi
  package_json="$(package_query "${requested}")"
  [ -n "${package_json}" ] || die "package not found in repository: ${requested}"
  name="$(printf '%s\n' "${package_json}" | "${JQ}" -r '.name')"
  plan_seen_mark "${requested}"
  plan_seen_mark "${name}"

  if dependency_satisfied "${name}"; then
    [ "${AUZIX_PLAN_VERBOSE:-0}" = "1" ] && echo "Plan satisfied ${name}" >&2
    # An installed parent is not proof that its dependency closure is still
    # present. Images may be assembled from receipts and repository artifacts
    # in separate stages, so always audit the parent's declared dependencies.
    package_is_satisfied=1
  fi
  if [ "${package_is_satisfied}" != "1" ]; then
    guard_substrate_install "${name}" "plan:${requested}" >/dev/null 2>&1 || {
    guard_rc=$?
    if [ "${guard_rc}" = "1" ]; then
      [ "${AUZIX_PLAN_VERBOSE:-0}" = "1" ] && echo "Plan substrate-satisfied ${name}" >&2
      return 0
    fi
    return 0
    }
  fi
  case " ${stack} " in
    *" ${name} "*)
      [ "${AUZIX_PLAN_VERBOSE:-0}" = "1" ] && echo "Plan cycle-skip ${name}" >&2
      return 0
      ;;
  esac

  if [ "${AUZIX_SKIP_DEPS:-0}" != "1" ]; then
    printf '%s\n' "${package_json}" | "${JQ}" -r '.depends[]? | select(. != null and . != "")' |
      while IFS= read -r dependency; do
        [ -n "${dependency}" ] || continue
        [ "${dependency}" != "null" ] || continue
        [ "${dependency}" = "${name}" ] && continue
        guard_substrate_install "${dependency}" "plan:${name}" >/dev/null 2>&1 || {
          guard_rc=$?
          [ "${guard_rc}" = "1" ] && continue
          continue
        }
        if ! dependency_satisfied "${dependency}"; then
          plan_one "${dependency}" "${stack} ${name}"
        fi
      done
    fail_if_blocked
  fi

  if ! dependency_satisfied "${name}" && ! plan_output_has "${name}"; then
    plan_output_mark "${name}"
    [ "${AUZIX_PLAN_VERBOSE:-0}" = "1" ] && echo "Plan add ${name}" >&2
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
    "${BB}" rm -rf "${LOOKUP_DIR}"
    prepare_package_lookup
    echo "Refreshed ${url}: $("${JQ}" '.packages | length' "${CACHE_INDEX}") packages"
    ;;
  refresh-ldcache)
    refresh_runtime_linker
    echo "Refreshed AUZiX runtime linker cache"
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
    plan_file="${WORK}/plan.$$.names"
    plan_json="${WORK}/plan.$$.json"
    resolve_plan_json "$1" "${plan_file}" "${plan_json}"
    fail_if_blocked
    echo "PLAN package=$1 new_packages=$("${BB}" wc -l <"${plan_file}")"
    cat "${plan_file}"
    ;;
  pull)
    require_index
    [ "$#" -eq 1 ] || die "pull requires a package name"
    acquire_transaction_lock "pull $1"
    export AUZIX_PULL_ONLY=1
    export AUZIX_PLAN_VERBOSE="${AUZIX_PLAN_VERBOSE:-1}"
    plan_file="${WORK}/pull-plan.$$.names"
    plan_json="${WORK}/pull-plan.$$.json"
    echo "PLANNING package=$1 mode=pull"
    resolve_plan_json "$1" "${plan_file}" "${plan_json}"
    fail_if_blocked
    echo "PULL_PLAN package=$1 new_packages=$("${BB}" wc -l <"${plan_file}")"
    cat "${plan_file}"
    echo "PREFETCH_BEGIN package=$1 archives_dir=${CACHE}"
    prefetch_plan_file "${plan_file}" "$1"
    fail_if_blocked
    echo "PULL_ARCHIVES package=$1 count=$("${BB}" find "${CACHE}" -type f -name '*.auzix.tar.gz' 2>/dev/null | "${BB}" wc -l)"
    echo "PULL_DONE package=$1 archives_dir=${CACHE}"
    ;;
  install|update)
    require_index
    [ "$#" -eq 1 ] || die "${command_name} requires a package name"
    acquire_transaction_lock "${command_name} $1"
    export AUZIX_PLAN_VERBOSE="${AUZIX_PLAN_VERBOSE:-1}"
    plan_file="${WORK}/${command_name}-plan.$$.names"
    plan_json="${WORK}/${command_name}-plan.$$.json"
    echo "PLANNING package=$1 mode=${command_name}"
    resolve_plan_json "$1" "${plan_file}" "${plan_json}"
    fail_if_blocked
    echo "INSTALL_PLAN package=$1 mode=${command_name} new_packages=$("${BB}" wc -l <"${plan_file}")"
    cat "${plan_file}"
    assert_plan_runtime_compatible "${plan_file}"
    echo "PREFETCH_BEGIN package=$1 archives_dir=${CACHE}"
    export AUZIX_PULL_ONLY=1
    prefetch_plan_file "${plan_file}" "$1"
    unset AUZIX_PULL_ONLY
    fail_if_blocked
    reset_transaction_marks
    seed_provided_state
    export AUZIX_DEFER_DESKTOP_REFRESH=1
    install_plan_file "${plan_file}" "$1"
    unset AUZIX_DEFER_DESKTOP_REFRESH
    fail_if_blocked
    package_json="$(package_query "$1")"
    if [ -n "${package_json}" ]; then
      archive="$(archive_path_for_package "${package_json}")"
      [ -s "${archive}" ] && refresh_desktop_surface "${package_json}" "${archive}"
    fi
    ;;
  install-one)
    require_index
    [ "$#" -eq 1 ] || die "install-one requires a package name"
    acquire_transaction_lock "install-one $1"
    seed_provided_state
    package_json="$(package_query "$1")"
    [ -n "${package_json}" ] || die "package not found in repository: $1"
    fetch_package_archive "${package_json}"
    AUZIX_SKIP_DEPS=1 install_one "$1" ""
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

auzix_build_link_ensure() {
  local target="$1"
  local link_path="$2"

  # PACKAGE OWNERSHIP:
  # Build-time command exports are owned by this package. A matching symlink is
  # a successful no-op; a different link/file/dir is a conflict. Do not change
  # this helper back to `ln -sfn` because live transactions must never learn
  # force-link habits from build scripts.
  if [[ -L "${link_path}" ]]; then
    local current_target
    current_target="$(readlink "${link_path}")"
    if [[ "${current_target}" == "${target}" ]]; then
      return 0
    fi
    printf 'AuzixPackageTools link conflict: %s -> %s, wanted %s\n' \
      "${link_path}" "${current_target}" "${target}" >&2
    return 1
  fi
  if [[ -e "${link_path}" ]]; then
    printf 'AuzixPackageTools link conflict: %s exists and is not a symlink\n' \
      "${link_path}" >&2
    return 1
  fi
  ln -s "${target}" "${link_path}"
}

auzix_build_link_ensure "/Programs/AuzixPackageTools/${PACKAGE_VERSION}" "${AUZIX_ROOT}/Programs/AuzixPackageTools/current"
auzix_build_link_ensure /Programs/AuzixPackageTools/current/Commands/jq "${AUZIX_ROOT}/System/Compatibility/bin/jq"
auzix_build_link_ensure /Programs/AuzixPackageTools/current/Commands/jq "${AUZIX_ROOT}/System/Compatibility/usr/bin/jq"
auzix_build_link_ensure /Programs/AuzixPackageTools/current/Commands/auzix-pkg "${AUZIX_ROOT}/System/Compatibility/bin/auzix-pkg"
auzix_build_link_ensure /Programs/AuzixPackageTools/current/Commands/auzix-pkg "${AUZIX_ROOT}/System/Compatibility/usr/bin/auzix-pkg"
auzix_build_link_ensure /Programs/AuzixPackageTools/current/Commands/auzix-pkg "${AUZIX_ROOT}/System/Tools/auzix-pkg"

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
