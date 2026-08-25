#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="${AUZIX_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_DIR="${AUZIX_REBASE_OUT:-${ROOT_DIR}/out/rebase/${RUN_ID}}"
LOCK_TAG="${AUZIX_REBASE_LOCK_TAG:-auzix-base-lock-${RUN_ID}}"
GIT_TAG="${AUZIX_REBASE_GIT_TAG:-auzix-alpha-base-${RUN_ID}}"
DEBIAN_SUITE="${AUZIX_DEBIAN_SUITE:-trixie}"
DEBIAN_ARCH="${AUZIX_DEBIAN_ARCH:-amd64}"
APT_SIMULATE_SECONDS="${AUZIX_APT_SIMULATE_SECONDS:-20}"
BASE_MANIFEST="${AUZIX_BASE_PORTS_MANIFEST:-${ROOT_DIR}/packages/base-ports.manifest.json}"
EXTENDED_MANIFEST="${AUZIX_EXTENDED_PORTS_MANIFEST:-${ROOT_DIR}/packages/extended-ports.manifest.json}"
BASE_RELEASE="${AUZIX_BASE_RELEASE:-${ROOT_DIR}/packages/auzix-base-release.alpha-0.0.1.json}"
PROFILE="${1:-${ROOT_DIR}/profiles/packages/auzix-vmid132-workstation.packages}"

log() {
  printf '[auzix-native-rebase-plan] %s\n' "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

safe_name() {
  tr '/: +' '---' <<<"$1" | tr -cd 'A-Za-z0-9_.+~-'
}

package_version() {
  local pkg="$1"
  command -v apt-cache >/dev/null 2>&1 || return 0
  apt-cache policy "${pkg}" 2>/dev/null |
    awk '/Candidate:/ {print $2; exit}'
}

debian_provider_name() {
  case "$1" in
    AuzixServiceRuntime) printf 'auzix-service-runtime\n' ;;
    CACerts) printf 'ca-certificates\n' ;;
    Cairo) printf 'libcairo2\n' ;;
    Curl) printf 'curl\n' ;;
    DBus) printf 'dbus\n' ;;
    DesktopFileUtils) printf 'desktop-file-utils\n' ;;
    EFL) printf 'efl\n' ;;
    Enlightenment) printf 'enlightenment\n' ;;
    Fontconfig) printf 'fontconfig\n' ;;
    Freetype) printf 'libfreetype6\n' ;;
    GCC14Base) printf 'gcc-14-base\n' ;;
    GdkPixbufLoaders) printf 'libgdk-pixbuf-2.0-0\n' ;;
    GLib) printf 'libglib2.0-0t64\n' ;;
    GSettingsDesktopSchemas) printf 'gsettings-desktop-schemas\n' ;;
    GTK3) printf 'libgtk-3-0t64\n' ;;
    GTK4) printf 'libgtk-4-1\n' ;;
    GtkUpdateIconCache) printf 'gtk-update-icon-cache\n' ;;
    Harfbuzz) printf 'libharfbuzz0b\n' ;;
    Libatomic1) printf 'libatomic1\n' ;;
    Libcrypto3t64) printf 'libssl3t64\n' ;;
    Libcurl4t64) printf 'libcurl4t64\n' ;;
    Libc6) printf 'libc6\n' ;;
    Libedje1) printf 'libedje1\n' ;;
    Libefreet1a) printf 'libefreet1a\n' ;;
    Libeina1t64) printf 'libeina1t64\n' ;;
    Libelementary1) printf 'libelementary1\n' ;;
    Libevas1) printf 'libevas1\n' ;;
    LibgccS1) printf 'libgcc-s1\n' ;;
    Libinput10) printf 'libinput10\n' ;;
    Libseccomp2) printf 'libseccomp2\n' ;;
    Libssl3t64) printf 'libssl3t64\n' ;;
    Libstdc6) printf 'libstdc++6\n' ;;
    Libx116) printf 'libx11-6\n' ;;
    Libxcb1) printf 'libxcb1\n' ;;
    Libxkbcommon0) printf 'libxkbcommon0\n' ;;
    Mesa) printf 'mesa-utils\n' ;;
    OpenSSL) printf 'openssl\n' ;;
    PAM) printf 'libpam0g\n' ;;
    Pango) printf 'libpango-1.0-0\n' ;;
    Polkit) printf 'polkitd\n' ;;
    SharedMimeInfo) printf 'shared-mime-info\n' ;;
    Systemd) printf 'systemd\n' ;;
    Terminology) printf 'terminology\n' ;;
    Udev) printf 'udev\n' ;;
    Xorg) printf 'xorg\n' ;;
    XorgServer) printf 'xserver-xorg-core\n' ;;
    Zlib1g) printf 'zlib1g\n' ;;
    *)
      printf '%s\n' "$1" |
        sed -E 's/([a-z0-9])([A-Z])/\1-\2/g; s/t64$/t64/' |
        tr '[:upper:]' '[:lower:]'
      ;;
  esac
}

require_cmd jq
require_cmd awk

mkdir -p "${OUT_DIR}"

[[ -s "${BASE_MANIFEST}" ]] || { log "missing base manifest: ${BASE_MANIFEST}"; exit 1; }
[[ -s "${BASE_RELEASE}" ]] || { log "missing base release: ${BASE_RELEASE}"; exit 1; }
[[ -s "${PROFILE}" ]] || { log "missing package profile: ${PROFILE}"; exit 1; }

cp -f "${BASE_MANIFEST}" "${OUT_DIR}/base-ports.manifest.json"
[[ -s "${EXTENDED_MANIFEST}" ]] && cp -f "${EXTENDED_MANIFEST}" "${OUT_DIR}/extended-ports.manifest.json"
cp -f "${BASE_RELEASE}" "${OUT_DIR}/base-release.json"
cp -f "${PROFILE}" "${OUT_DIR}/requested.packages"

awk '
  /^[[:space:]]*($|#)/ { next }
  { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if (!seen[$0]++) print $0 }
' "${PROFILE}" >"${OUT_DIR}/requested.normalized"

jq -r '
  .phases[] as $phase |
  ($phase.targets // [])[] |
  [$phase.id, .name, .source.kind, .source.package, (.source.version // "unspecified"), .prefix, ((.promotes // []) | join(","))] |
  @tsv
' "${BASE_MANIFEST}" >"${OUT_DIR}/base-chain.tsv"

if [[ -s "${EXTENDED_MANIFEST}" ]]; then
  jq -r '
    .phases[]? as $phase |
    ($phase.targets // [])[]? |
    [$phase.id, .name, .source.kind, .source.package, (.source.version // "unspecified"), .prefix, ((.promotes // []) | join(","))] |
    @tsv
  ' "${EXTENDED_MANIFEST}" >"${OUT_DIR}/extended-chain.tsv"
else
  : >"${OUT_DIR}/extended-chain.tsv"
fi

{
  printf 'tier\tphase\tname\tsource_kind\tsource_package\tsource_version\tprefix\tpromotes\n'
  awk 'BEGIN{FS=OFS="\t"} {print "base",$0}' "${OUT_DIR}/base-chain.tsv"
  awk 'BEGIN{FS=OFS="\t"} NF {print "extended",$0}' "${OUT_DIR}/extended-chain.tsv"
} >"${OUT_DIR}/package-chain.tsv"

{
  printf 'suite=%s\n' "${DEBIAN_SUITE}"
  printf 'arch=%s\n' "${DEBIAN_ARCH}"
  if command -v apt-cache >/dev/null 2>&1; then
    apt-cache policy 2>/dev/null || true
  fi
} >"${OUT_DIR}/debian-current-head.policy.txt"

if command -v apt-cache >/dev/null 2>&1; then
  apt-cache dumpavail |
    awk '
      /^Package: / {pkg=$2; next}
      /^Version: / && pkg != "" && !(pkg in version) {version[pkg]=$2; pkg=""; next}
      END {for (pkg in version) print pkg "\t" version[pkg]}
    ' |
    sort >"${OUT_DIR}/apt-candidates.tsv"
else
  : >"${OUT_DIR}/apt-candidates.tsv"
fi

{
  printf 'package\tcandidate_version\trequest_state\n'
  awk 'BEGIN{FS=OFS="\t"}
    NR == FNR {candidate[$1]=$2; next}
    {
    version=candidate[$1]
    if (version == "") print $1, "metadata-unavailable", "unresolved-or-virtual"
    else print $1, version, "requested-selected"
  }
  ' "${OUT_DIR}/apt-candidates.tsv" "${OUT_DIR}/requested.normalized"
} >"${OUT_DIR}/current-head-versions.tsv"

awk 'BEGIN{FS="\t"} NR > 1 && $3 == "requested-selected" {print $1}' \
  "${OUT_DIR}/current-head-versions.tsv" >"${OUT_DIR}/requested.resolved"
awk 'BEGIN{FS="\t"} NR > 1 && $3 != "requested-selected" {print $1 "\t" $2 "\t" $3}' \
  "${OUT_DIR}/current-head-versions.tsv" >"${OUT_DIR}/requested.unresolved"

if command -v apt-cache >/dev/null 2>&1; then
  xargs -a "${OUT_DIR}/requested.resolved" apt-cache depends \
    --no-conflicts --no-breaks --no-replaces --no-enhances \
    --no-suggests --no-recommends 2>/dev/null |
    awk '
      /^[[:alnum:]][^ <|]*$/ { current=$1; next }
      /Depends:/ {
        dep=$2
        gsub(/[<>]/, "", dep)
        if (current != "" && dep != "" && dep !~ /^</ && !seen[current "\t" dep]++) {
          print "direct\t" current "\t" dep
        }
      }
    ' >"${OUT_DIR}/dependency-chain.tsv" || true
else
  log "apt-cache unavailable; dependency-chain.tsv will contain requested roots only"
  awk '{print $0 "\t" $0 "\t(metadata-unavailable)"}' "${OUT_DIR}/requested.normalized" >"${OUT_DIR}/dependency-chain.tsv"
fi

apt_simulation_status="not-run"
if command -v apt-get >/dev/null 2>&1 && [[ -s "${OUT_DIR}/requested.resolved" ]]; then
  apt_simulation_status="ok"
  if command -v timeout >/dev/null 2>&1; then
    xargs -a "${OUT_DIR}/requested.resolved" timeout "${APT_SIMULATE_SECONDS}" apt-get -s install --no-install-recommends >"${OUT_DIR}/apt-simulate.log" 2>"${OUT_DIR}/apt-simulate.stderr" ||
      apt_simulation_status="timeout-or-error"
  else
    xargs -a "${OUT_DIR}/requested.resolved" apt-get -s install --no-install-recommends >"${OUT_DIR}/apt-simulate.log" 2>"${OUT_DIR}/apt-simulate.stderr" ||
      apt_simulation_status="error"
  fi
  awk '/^Inst / {print $2}' "${OUT_DIR}/apt-simulate.log" |
    awk 'NF && !seen[$0]++ {print $0}' |
    sort >"${OUT_DIR}/selected-package-set.txt"
  if [[ ! -s "${OUT_DIR}/selected-package-set.txt" ]]; then
    apt_simulation_status="${apt_simulation_status}-fallback-direct-deps"
    awk 'BEGIN{FS="\t"} {print $2; print $3}' "${OUT_DIR}/dependency-chain.tsv" |
      awk 'NF && $0 != "metadata-unavailable" && !seen[$0]++ {print $0}' |
      sort >"${OUT_DIR}/selected-package-set.txt"
  fi
else
  apt_simulation_status="fallback-direct-deps"
  awk 'BEGIN{FS="\t"} {print $2; print $3}' "${OUT_DIR}/dependency-chain.tsv" |
    awk 'NF && $0 != "metadata-unavailable" && !seen[$0]++ {print $0}' |
    sort >"${OUT_DIR}/selected-package-set.txt"
fi

# A substrate declaration is a build requirement, not evidence that its
# provider is already present.  Force every resolvable Debian provider from
# the locked AUZiX base into the selected set before leaf packages are built.
# Runtime validation will separately require the receipt and payload files in
# the assembled root.
while IFS= read -r substrate_package; do
  provider="$(debian_provider_name "${substrate_package}")"
  version="$(package_version "${provider}")"
  [[ -n "${version}" && "${version}" != "(none)" ]] || continue
  printf '%s\n' "${provider}"
done < <(jq -r '.runtime_substrate[].packages[]' "${BASE_RELEASE}") \
  >>"${OUT_DIR}/selected-package-set.txt"
sort -u -o "${OUT_DIR}/selected-package-set.txt" "${OUT_DIR}/selected-package-set.txt"

{
  printf 'package\tcandidate_version\tselection_state\n'
  awk 'BEGIN{FS=OFS="\t"}
    NR == FNR {candidate[$1]=$2; next}
    {
      version=candidate[$1]
      if (version == "") print $1, "metadata-unavailable", "unresolved-or-virtual"
      else print $1, version, "selected"
    }
  ' "${OUT_DIR}/apt-candidates.tsv" "${OUT_DIR}/selected-package-set.txt"
} >"${OUT_DIR}/selected-current-head.tsv"

{
  printf 'substrate_id\ttier\tpackage\tcandidate_version\tprovider_state\n'
  jq -r '.runtime_substrate[] | . as $s | .packages[] | [$s.id, $s.tier, .] | @tsv' "${BASE_RELEASE}" |
  while IFS=$'\t' read -r substrate_id tier package; do
    debian_name="$(debian_provider_name "${package}")"
    version="$(awk -F '\t' -v pkg="${debian_name}" '$1 == pkg {print $2; exit}' "${OUT_DIR}/apt-candidates.tsv")"
    if [[ -z "${version}" || "${version}" == "(none)" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\n' "${substrate_id}" "${tier}" "${package}" "${version:-metadata-unavailable}" "auzix-or-unresolved"
    else
      printf '%s\t%s\t%s\t%s\t%s\n' "${substrate_id}" "${tier}" "${package}" "${version}" "selected-provider"
    fi
  done
} >"${OUT_DIR}/substrate-provider-lock.tsv"

requested_count="$(wc -l <"${OUT_DIR}/requested.normalized" | tr -d ' ')"
requested_unresolved_count="$(awk 'BEGIN{FS="\t"} NR > 1 && $3 != "requested-selected" {count++} END{print count + 0}' "${OUT_DIR}/current-head-versions.tsv")"
selected_count="$(awk 'NR > 1 && $3 == "selected" {count++} END{print count + 0}' "${OUT_DIR}/selected-current-head.tsv")"
unresolved_count="$(awk 'NR > 1 && $3 != "selected" {count++} END{print count + 0}' "${OUT_DIR}/selected-current-head.tsv")"
substrate_provider_count="$(awk 'NR > 1 {count++} END{print count + 0}' "${OUT_DIR}/substrate-provider-lock.tsv")"
substrate_selected_count="$(awk 'NR > 1 && $5 == "selected-provider" {count++} END{print count + 0}' "${OUT_DIR}/substrate-provider-lock.tsv")"
dependency_edge_count="$(wc -l <"${OUT_DIR}/dependency-chain.tsv" | tr -d ' ')"
unique_dependency_count="$(
  awk 'BEGIN{FS="\t"} {print $3}' "${OUT_DIR}/dependency-chain.tsv" |
    awk 'NF && !seen[$0]++ {count++} END{print count + 0}'
)"
base_target_count="$(jq '[.phases[].targets[]] | length' "${BASE_MANIFEST}")"
extended_target_count="$(
  if [[ -s "${EXTENDED_MANIFEST}" ]]; then
    jq '[.phases[]?.targets[]?] | length' "${EXTENDED_MANIFEST}"
  else
    printf '0\n'
  fi
)"

jq -n \
  --arg format "auzix-native-rebase-manifest-v1" \
  --arg status "planned-no-compile" \
  --arg run_id "${RUN_ID}" \
  --arg lock_tag "${LOCK_TAG}" \
  --arg git_tag "${GIT_TAG}" \
  --arg profile "${PROFILE}" \
  --arg base_release "${BASE_RELEASE}" \
  --arg debian_suite "${DEBIAN_SUITE}" \
  --arg debian_arch "${DEBIAN_ARCH}" \
  --slurpfile base "${BASE_MANIFEST}" \
  --slurpfile release "${BASE_RELEASE}" \
  --rawfile requested "${OUT_DIR}/requested.normalized" \
  '{
    format: $format,
    status: $status,
    run_id: $run_id,
    lock_tag: $lock_tag,
    git_tag: $git_tag,
    suggested_git_tag: $git_tag,
    profile: $profile,
    base_release: $base_release,
    upstream_lane: {
      distribution: "debian",
      suite: $debian_suite,
      arch: $debian_arch,
      rule: "select one candidate version per package from this lane; variants and virtuals must resolve before compile"
    },
    compile_enabled: false,
    rule: "Current-head versions are selected and locked before compile. Do not compile until this manifest is reviewed and promoted to compile_enabled=true by the pipeline.",
    distro_model: {
      reference: "Slackware/Debian-style package build ordering",
      auzix_delta: "AUZiX paths, substrate lock, package receipts, and native-container authority"
    },
    base_substrate: $release[0].runtime_substrate,
    base_ports_phases: $base[0].phases,
    requested_packages: ($requested | split("\n") | map(select(length > 0))),
    build_order_contract: [
      "discovery metadata",
      "tag and lock build tree",
      "base substrate libraries",
      "base substrate dev surfaces",
      "acid/base AUZiX native builder container",
      "AUZiX builds AUZiX leaf apps inside the native builder",
      "package validation container/root",
      "VM smoke"
    ],
    artifact_policy: {
      old_artifacts: "quarantine",
      app_local_substrate_libraries: "forbidden",
      debian: "reference/feedstock only",
      compile_input: "locked tree only",
      git_ref_required: "commit and tag the discovered lock before build",
      tag_drift: "zero drift; builds consume the exact tag/ref containing this lock",
      build_helpers: "jq/awk/gawk/rq/apt metadata tools are allowed in the factory toolchain without becoming target payload",
      minor_version_drift: "allowed only as a declared compatibility range on the selected provider; never as a parallel substrate copy"
    }
  }' >"${OUT_DIR}/final-package-manifest.json"

{
  printf 'order\ttier\tphase\tname\tsource_package\tmode\n'
  jq -r '
    [ .phases[] as $phase |
      ($phase.targets // [])[] |
      [$phase.id, .name, .source.package]
    ] | to_entries[] |
    [(.key + 1), "base", .value[0], .value[1], .value[2], "base-dev-first"] | @tsv
  ' "${BASE_MANIFEST}"
  awk -v offset="${base_target_count}" 'BEGIN{OFS="\t"} {print NR+offset, "app-request", "requested-profile", $1, $1, "after-auzix-native-container"}' "${OUT_DIR}/requested.normalized"
} >"${OUT_DIR}/compile-order.tsv"

find "${OUT_DIR}" -maxdepth 1 -type f \
  \( -name '*.json' -o -name '*.tsv' -o -name '*.packages' -o -name '*.normalized' \) \
  ! -name 'build-tree.lock.json' \
  ! -name 'plan-report.json' \
  -print0 |
  sort -z |
  xargs -0 sha256sum >"${OUT_DIR}/manifest-material.sha256"

manifest_lock_sha256="$(sha256sum "${OUT_DIR}/manifest-material.sha256" | awk '{print $1}')"

jq -n \
  --arg format "auzix-native-rebase-lock-v1" \
  --arg status "locked-no-compile" \
  --arg run_id "${RUN_ID}" \
  --arg lock_tag "${LOCK_TAG}" \
  --arg git_tag "${GIT_TAG}" \
  --arg locked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg manifest_lock_sha256 "${manifest_lock_sha256}" \
  --arg manifest_material "${OUT_DIR}/manifest-material.sha256" \
  --arg compile_order "${OUT_DIR}/compile-order.tsv" \
  --arg current_head_versions "${OUT_DIR}/current-head-versions.tsv" \
  --arg selected_current_head "${OUT_DIR}/selected-current-head.tsv" \
  --arg substrate_provider_lock "${OUT_DIR}/substrate-provider-lock.tsv" \
  --arg debian_policy "${OUT_DIR}/debian-current-head.policy.txt" \
  --arg apt_simulation_status "${apt_simulation_status}" \
  --argjson requested_count "${requested_count}" \
  --argjson requested_unresolved_count "${requested_unresolved_count}" \
  --argjson dependency_edge_count "${dependency_edge_count}" \
  --argjson unique_dependency_count "${unique_dependency_count}" \
  --argjson base_target_count "${base_target_count}" \
  --argjson extended_target_count "${extended_target_count}" \
  --argjson selected_count "${selected_count}" \
  --argjson unresolved_count "${unresolved_count}" \
  --argjson substrate_provider_count "${substrate_provider_count}" \
  --argjson substrate_selected_count "${substrate_selected_count}" \
  '{
    format: $format,
    status: $status,
    run_id: $run_id,
    lock_tag: $lock_tag,
    suggested_git_tag: $git_tag,
    locked_at: $locked_at,
    manifest_lock_sha256: $manifest_lock_sha256,
    manifest_material: $manifest_material,
    compile_order: $compile_order,
    current_head_versions: $current_head_versions,
    selected_current_head: $selected_current_head,
    substrate_provider_lock: $substrate_provider_lock,
    debian_policy: $debian_policy,
    apt_simulation_status: $apt_simulation_status,
    counts: {
      requested_roots: $requested_count,
      requested_unresolved_or_virtual_roots: $requested_unresolved_count,
      dependency_edges: $dependency_edge_count,
      unique_dependency_packages: $unique_dependency_count,
      selected_unique_packages: $selected_count,
      unresolved_or_virtual_packages: $unresolved_count,
      substrate_providers: $substrate_provider_count,
      substrate_selected_providers: $substrate_selected_count,
      base_targets: $base_target_count,
      extended_targets: $extended_target_count,
      planned_total_before_dependency_expansion: ($requested_count + $base_target_count + $extended_target_count)
    },
    allowed_first_builds: [
      "BusyBox",
      "Lua",
      "CACerts",
      "Zlib",
      "OpenSSL",
      "Curl",
      "PkgConfig",
      "Make",
      "CMake",
      "Meson",
      "Ninja"
    ],
    rule: "Only this locked manifest tree may build the AUZiX BusyBox/base/build-toolchain stage. Commit and tag this lock before builders consume it. That acid/base AUZiX container becomes the authority; leaf apps wait until AUZiX can build AUZiX."
  }' >"${OUT_DIR}/build-tree.lock.json"

jq -n \
  --arg format "auzix-native-rebase-plan-report-v1" \
  --arg status "planned-no-compile" \
  --arg out_dir "${OUT_DIR}" \
  --arg lock_tag "${LOCK_TAG}" \
  --arg git_tag "${GIT_TAG}" \
  --arg lock "${OUT_DIR}/build-tree.lock.json" \
  --arg manifest "${OUT_DIR}/final-package-manifest.json" \
  --arg compile_order "${OUT_DIR}/compile-order.tsv" \
  --arg dependency_chain "${OUT_DIR}/dependency-chain.tsv" \
  --arg package_chain "${OUT_DIR}/package-chain.tsv" \
  --arg current_head_versions "${OUT_DIR}/current-head-versions.tsv" \
  --arg selected_current_head "${OUT_DIR}/selected-current-head.tsv" \
  --arg substrate_provider_lock "${OUT_DIR}/substrate-provider-lock.tsv" \
  --arg debian_policy "${OUT_DIR}/debian-current-head.policy.txt" \
  --arg apt_simulation_status "${apt_simulation_status}" \
  --argjson requested_count "${requested_count}" \
  --argjson requested_unresolved_count "${requested_unresolved_count}" \
  --argjson base_count "${base_target_count}" \
  --argjson extended_count "${extended_target_count}" \
  --argjson dependency_edge_count "${dependency_edge_count}" \
  --argjson unique_dependency_count "${unique_dependency_count}" \
  --argjson selected_count "${selected_count}" \
  --argjson unresolved_count "${unresolved_count}" \
  --argjson substrate_provider_count "${substrate_provider_count}" \
  --argjson substrate_selected_count "${substrate_selected_count}" \
  '{
    format: $format,
    status: $status,
    out_dir: $out_dir,
    lock_tag: $lock_tag,
    suggested_git_tag: $git_tag,
    lock: $lock,
    manifest: $manifest,
    compile_order: $compile_order,
    dependency_chain: $dependency_chain,
    package_chain: $package_chain,
    current_head_versions: $current_head_versions,
    selected_current_head: $selected_current_head,
    substrate_provider_lock: $substrate_provider_lock,
    debian_policy: $debian_policy,
    apt_simulation_status: $apt_simulation_status,
    requested_count: $requested_count,
    requested_unresolved_or_virtual_count: $requested_unresolved_count,
    base_target_count: $base_count,
    extended_target_count: $extended_count,
    dependency_edge_count: $dependency_edge_count,
    unique_dependency_count: $unique_dependency_count,
    selected_unique_packages: $selected_count,
    unresolved_or_virtual_packages: $unresolved_count,
    substrate_provider_count: $substrate_provider_count,
    substrate_selected_provider_count: $substrate_selected_count,
    planned_total_before_dependency_expansion: ($requested_count + $base_count + $extended_count),
    next_gate: "review final-package-manifest.json, compile-order.tsv, and build-tree.lock.json; only then run locked base/dev build"
  }' >"${OUT_DIR}/plan-report.json"

log "plan: ${OUT_DIR}/final-package-manifest.json"
log "lock: ${OUT_DIR}/build-tree.lock.json"
log "compile order: ${OUT_DIR}/compile-order.tsv"
log "dependency chain: ${OUT_DIR}/dependency-chain.tsv"
log "current head versions: ${OUT_DIR}/current-head-versions.tsv"
log "selected current head: ${OUT_DIR}/selected-current-head.tsv"
log "substrate provider lock: ${OUT_DIR}/substrate-provider-lock.tsv"
log "report: ${OUT_DIR}/plan-report.json"
