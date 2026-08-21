#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT="${AUZIX_ROOT:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
DEBIAN_SUITE="${AUZIX_DEBIAN_SUITE:-trixie}"
DEBIAN_PACKAGE=""
DEB_PATH=""
LINT_RECIPES=""

log() {
  printf '[auzix-release-lane] %s\n' "$*" >&2
}

usage() {
  cat >&2 <<'EOF'
Usage:
  preflight-auzix-release-lane.sh [--root PATH] [--suite SUITE] [--package NAME] [--deb PATH]
  preflight-auzix-release-lane.sh [--root PATH] [--suite SUITE] --lint-recipes DIR

Checks that AUZiX package intake stays in one Debian release lane and does not
package binaries that require a newer core glibc than the active AUZiX root.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      AUZIX_ROOT="${2:?missing --root value}"
      shift 2
      ;;
    --suite)
      DEBIAN_SUITE="${2:?missing --suite value}"
      shift 2
      ;;
    --package)
      DEBIAN_PACKAGE="${2:?missing --package value}"
      shift 2
      ;;
    --deb)
      DEB_PATH="${2:?missing --deb value}"
      shift 2
      ;;
    --lint-recipes)
      LINT_RECIPES="${2:?missing --lint-recipes value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log "unknown argument: $1"
      usage
      exit 2
      ;;
  esac
done

max_glibc_symbol_in_file() {
  local file="$1"
  strings "$file" 2>/dev/null | grep -E '^GLIBC_[0-9]+[.][0-9]+' | sort -V | tail -n 1 || true
}

version_gt() {
  local a="$1"
  local b="$2"
  [[ -n "$a" && -n "$b" ]] || return 1
  [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n 1)" == "$a" && "$a" != "$b" ]]
}

check_recipe_lanes() {
  local recipe_dir="$1"
  local failed=0
  command -v jq >/dev/null 2>&1 || {
    log "missing command for recipe lint: jq"
    exit 2
  }
  [[ -d "$recipe_dir" ]] || {
    log "recipe directory not found: $recipe_dir"
    exit 2
  }

  while IFS= read -r -d '' recipe; do
    local format name source_type source_suite
    format="$(jq -r '.format // empty' "$recipe")"
    [[ "$format" == "auzix-command-suite-v1" ]] || continue
    name="$(jq -r '.name // empty' "$recipe")"
    source_type="$(jq -r '.source.type // empty' "$recipe")"
    source_suite="$(jq -r '.source.suite // empty' "$recipe")"

    if [[ "$source_type" == "host-binary" ]]; then
      log "FAIL recipe=${recipe#${ROOT_DIR}/} name=${name:-unknown} source.type=host-binary is not allowed in strict ${DEBIAN_SUITE} lane"
      failed=1
    fi
    if [[ -n "$source_suite" && "$source_suite" != "$DEBIAN_SUITE" ]]; then
      log "FAIL recipe=${recipe#${ROOT_DIR}/} name=${name:-unknown} source.suite=${source_suite} expected=${DEBIAN_SUITE}"
      failed=1
    fi
  done < <(find "$recipe_dir" -type f -name '*.command-suite.json' -print0 | sort -z)

  if (( failed )); then
    log "strict release lane recipe lint failed"
    exit 42
  fi
  log "recipe lint passed suite=${DEBIAN_SUITE} dir=${recipe_dir#${ROOT_DIR}/}"
}

check_candidate_suite() {
  local package="$1"
  local candidate policy candidate_block
  command -v apt-cache >/dev/null 2>&1 || {
    log "missing command for suite check: apt-cache"
    exit 2
  }
  candidate="$(apt-cache policy "$package" | awk '/Candidate:/ {print $2; exit}')"
  [[ -n "$candidate" && "$candidate" != "(none)" ]] || {
    log "FAIL package=${package} has no apt candidate"
    exit 42
  }
  policy="$(apt-cache policy "$package")"
  candidate_block="$(awk -v candidate="$candidate" '
    $1 == candidate || ($1 == "***" && $2 == candidate) {capture=1; print; next}
    capture && /^[[:space:]]{5}[0-9]+[[:space:]]/ {print; next}
    capture && /^[[:space:]]{8,}/ {print; next}
    capture && /^[[:space:]]{3}[^[:space:]]/ {capture=0}
  ' <<<"$policy")"

  if ! grep -E "(^|[[:space:]/])${DEBIAN_SUITE}([[:space:]/]|$)" <<<"$candidate_block" >/dev/null 2>&1; then
    log "FAIL package=${package} candidate=${candidate} is not proven from suite=${DEBIAN_SUITE}"
    log "candidate policy block:"
    sed 's/^/[auzix-release-lane]   /' <<<"$candidate_block" >&2
    exit 42
  fi
  log "candidate ok package=${package} version=${candidate} suite=${DEBIAN_SUITE}"
}

check_deb_glibc_floor() {
  local package="$1"
  local deb="$2"
  local libc_path active_glibc temp_dir required_glibc

  [[ -f "$deb" ]] || {
    log "deb path not found: $deb"
    exit 2
  }
  command -v dpkg-deb >/dev/null 2>&1 || {
    log "missing command for deb check: dpkg-deb"
    exit 2
  }
  command -v file >/dev/null 2>&1 || {
    log "missing command for ELF check: file"
    exit 2
  }

  libc_path="${AUZIX_ROOT}/System/Libraries/Runtime/glibc/libc.so.6"
  [[ -f "$libc_path" ]] || {
    log "FAIL active AUZiX root has no core glibc at ${libc_path#${AUZIX_ROOT}/}"
    exit 42
  }
  active_glibc="$(max_glibc_symbol_in_file "$libc_path")"
  [[ -n "$active_glibc" ]] || {
    log "FAIL could not read active AUZiX glibc symbol floor from ${libc_path#${AUZIX_ROOT}/}"
    exit 42
  }

  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN
  dpkg-deb -x "$deb" "$temp_dir/root" >/dev/null
  required_glibc="$(
    while IFS= read -r -d '' candidate_file; do
      file "$candidate_file" 2>/dev/null | grep -q 'ELF' || continue
      max_glibc_symbol_in_file "$candidate_file"
    done < <(find "$temp_dir/root" -type f \( -perm /111 -o -name '*.so' -o -name '*.so.*' \) -print0) |
      sort -V | tail -n 1
  )"

  if [[ -n "$required_glibc" ]] && version_gt "$required_glibc" "$active_glibc"; then
    log "FAIL runtime-rebuild-required package=${package} deb=${deb##*/} requires=${required_glibc} active_root=${active_glibc}"
    exit 42
  fi

  log "glibc floor ok package=${package} required=${required_glibc:-none} active_root=${active_glibc}"
}

if [[ -n "$LINT_RECIPES" ]]; then
  check_recipe_lanes "$LINT_RECIPES"
fi

if [[ -n "$DEBIAN_PACKAGE" ]]; then
  check_candidate_suite "$DEBIAN_PACKAGE"
fi

if [[ -n "$DEB_PATH" ]]; then
  [[ -n "$DEBIAN_PACKAGE" ]] || DEBIAN_PACKAGE="$(dpkg-deb -f "$DEB_PATH" Package 2>/dev/null || printf unknown)"
  check_deb_glibc_floor "$DEBIAN_PACKAGE" "$DEB_PATH"
fi
