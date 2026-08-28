#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_script="${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh"

extract_functions="$(
  sed -n '1,/^command_name_allowed()/p' "${source_script}" |
    sed '$d'
)"

closure_tmp="$(mktemp -d)"
trap 'rm -rf "${closure_tmp}"' EXIT
mkdir -p "${closure_tmp}/db"
cat >"${closure_tmp}/db/Direct-1.auzix.json" <<'JSON'
{"name":"Direct","depends":[]}
JSON
cat >"${closure_tmp}/index.json" <<'JSON'
{"format":"auzix-repo-v1","packages":[
  {"name":"Direct","depends":["Transitive"]},
  {"name":"Transitive","depends":["Leaf"]},
  {"name":"Leaf","depends":[]}
]}
JSON
closure="$({ eval "${extract_functions}"; native_installed_depends_closure_words Direct "${closure_tmp}/db" "${closure_tmp}/index.json"; })"
[[ "${closure}" == "Direct Transitive Leaf" ]] || {
  printf 'repository-authoritative closure failed: %s\n' "${closure}" >&2
  exit 1
}

eval "${extract_functions}"

# This is a parser unit test; package availability belongs to the intake
# preflight and must not make the result depend on the host's APT sources.
debian_package_has_candidate() { return 0; }

sample='libc6 (>= 2.38), libncursesw6 (>= 6), libtinfo6 (>= 6), libglib2.0-0t64 (>= 2.75.3), libgtk-3-0t64 (>= 3.2.1), python3:any, libgcc-s1 (>= 3.0)'
parsed="$(debian_depends_to_native_json "${sample}")"

jq -e '
  index("Libc6") and
  index("Libncursesw6") and
  index("Libtinfo6") and
  index("Libglib200t64") and
  index("Libgtk30t64") and
  index("Python3") and
  index("LibgccS1")
' <<<"${parsed}" >/dev/null

printf 'AuziX Debian dependency parser: PASS %s\n' "${parsed}"
