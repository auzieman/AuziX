#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_script="${ROOT_DIR}/scripts/build-auzix-debian-intake-package.sh"

extract_functions="$(
  sed -n '1,/^command_name_allowed()/p' "${source_script}" |
    sed '$d'
)"

eval "${extract_functions}"

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
