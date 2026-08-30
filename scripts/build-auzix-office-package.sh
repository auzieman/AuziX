#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/auzix-library-policy.sh"
AUZIX_ROOT="${1:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
PACKAGE_ID="${2:-}"

case "${PACKAGE_ID}" in
  abiword)
    NAME="AbiWord"
    COMMANDS=(abiword)
    RESOURCE_DIRS=(abiword-3.0)
    LIBRARY_DIRS=(abiword-3.0)
    CATEGORIES="Office;WordProcessor;"
    ;;
  gnumeric)
    NAME="Gnumeric"
    COMMANDS=(gnumeric ssconvert ssdiff ssgrep ssindex)
    RESOURCE_DIRS=(gnumeric)
    LIBRARY_DIRS=(gnumeric)
    CATEGORIES="Office;Spreadsheet;"
    ;;
  *)
    printf 'Usage: %s AUZIX_ROOT {abiword|gnumeric}\n' "$0" >&2
    exit 2
    ;;
esac

log() {
  printf '[auzix-office] %s\n' "$*" >&2
}

for command_name in apt-get dpkg-query file install jq ldd rsync; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    log "missing command: ${command_name}"
    exit 1
  }
done
[[ -d "${AUZIX_ROOT}/System/PackageDB" ]] || {
  log "AuziX root is missing: ${AUZIX_ROOT}"
  exit 1
}

apt-get install -y --no-install-recommends "${PACKAGE_ID}" >/dev/null
VERSION="$(dpkg-query -W -f='${Version}' "${PACKAGE_ID}")"
SAFE_VERSION="$(tr '/: ' '---' <<<"${VERSION}" | tr -cd 'A-Za-z0-9_.+~-')"
PROGRAM="${AUZIX_ROOT}/Programs/${NAME}/${SAFE_VERSION}"
RUNTIME_USR="${AUZIX_ROOT}/System/Compatibility/usr"
RUNTIME_BIN="${AUZIX_ROOT}/System/Compatibility/bin"

rm -rf "${PROGRAM}"
mkdir -p \
  "${PROGRAM}/Commands" \
  "${PROGRAM}/Libraries" \
  "${PROGRAM}/Resources/usr/share" \
  "${PROGRAM}/Resources/usr/lib" \
  "${RUNTIME_BIN}" \
  "${RUNTIME_USR}/bin" \
  "${RUNTIME_USR}/share/applications"

copy_library() {
  local source="$1"
  local target="${PROGRAM}/Libraries/$(basename "${source}")"
  [[ -e "${source}" ]] || return 0
  [[ "$(readlink -f "${source}")" == "$(readlink -m "${target}")" ]] && return 0
  if auzix_forbid_app_local_library "${source}"; then
    log "substrate-skip $(auzix_library_policy_class "${source}") ${source}"
    return 0
  fi
  cp -aL --remove-destination "${source}" "${target}"
  chmod 0755 "${target}" 2>/dev/null || true
}

scan_elf_dependencies() {
  local scan_round=0
  local before_count after_count elf dep
  while (( scan_round < 8 )); do
    before_count="$(find "${PROGRAM}/Libraries" -maxdepth 1 -type f | wc -l)"
    while IFS= read -r elf; do
      file "${elf}" | grep -q 'ELF' || continue
      while IFS= read -r dep; do
        copy_library "${dep}"
      done < <(
        LD_LIBRARY_PATH="${PROGRAM}/Libraries" ldd "${elf}" 2>/dev/null |
          awk '{for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i}' |
          sort -u
      )
    done < <(find "${PROGRAM}/Commands" "${PROGRAM}/Libraries" "${PROGRAM}/Resources/usr/lib" -type f)
    after_count="$(find "${PROGRAM}/Libraries" -maxdepth 1 -type f | wc -l)"
    (( after_count == before_count )) && break
    scan_round=$((scan_round + 1))
  done
}

for command_name in "${COMMANDS[@]}"; do
  source_path="$(command -v "${command_name}" 2>/dev/null || true)"
  [[ -x "${source_path}" ]] || {
    log "installed command not found: ${command_name}"
    exit 1
  }
  install -m 0755 "${source_path}" "${PROGRAM}/Commands/${command_name}.real"
done

for resource_dir in "${RESOURCE_DIRS[@]}"; do
  [[ -d "/usr/share/${resource_dir}" ]] || continue
  rsync -a "/usr/share/${resource_dir}/" "${PROGRAM}/Resources/usr/share/${resource_dir}/"
  ln -sfn "/Programs/${NAME}/current/Resources/usr/share/${resource_dir}" \
    "${RUNTIME_USR}/share/${resource_dir}"
done
for library_dir in "${LIBRARY_DIRS[@]}"; do
  for source_dir in "/usr/lib/${library_dir}" "/usr/lib/x86_64-linux-gnu/${library_dir}"; do
    [[ -d "${source_dir}" ]] || continue
    target_dir="${PROGRAM}/Resources${source_dir}"
    mkdir -p "$(dirname "${target_dir}")"
    rsync -a "${source_dir}/" "${target_dir}/"
  done
done

for shared_dir in glib-2.0/schemas; do
  [[ -d "/usr/share/${shared_dir}" ]] || continue
  mkdir -p "${PROGRAM}/Resources/usr/share/${shared_dir}"
  rsync -a "/usr/share/${shared_dir}/" "${PROGRAM}/Resources/usr/share/${shared_dir}/"
done
for desktop_file in /usr/share/applications/*"${PACKAGE_ID}"*.desktop; do
  [[ -f "${desktop_file}" ]] || continue
  install -D -m 0644 "${desktop_file}" \
    "${PROGRAM}/Resources/usr/share/applications/$(basename "${desktop_file}")"
done
while IFS= read -r icon_file; do
  relative_icon="${icon_file#/usr/share/}"
  install -D -m 0644 "${icon_file}" "${PROGRAM}/Resources/usr/share/${relative_icon}"
done < <(
  find /usr/share/icons /usr/share/pixmaps -type f \
    \( -iname "*${PACKAGE_ID}*" -o -iname "*${NAME}*" \) 2>/dev/null
)
for module_dir in \
  /usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0 \
  /usr/lib/x86_64-linux-gnu/gtk-3.0; do
  [[ -d "${module_dir}" ]] || continue
  target_dir="${PROGRAM}/Resources${module_dir}"
  mkdir -p "$(dirname "${target_dir}")"
  rsync -a "${module_dir}/" "${target_dir}/"
done

scan_elf_dependencies
LOADER="/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2"

for command_name in "${COMMANDS[@]}"; do
  cat >"${PROGRAM}/Commands/${command_name}" <<EOF
#!/Programs/BusyBox/1.36.1/Commands/busybox sh
set -eu
export XDG_DATA_DIRS="/Programs/${NAME}/current/Resources/usr/share:/System/Compatibility/usr/share"
export GSETTINGS_SCHEMA_DIR="/Programs/${NAME}/current/Resources/usr/share/glib-2.0/schemas"
export GDK_PIXBUF_MODULEDIR="/Programs/${NAME}/current/Resources/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders"
export GTK_PATH="/Programs/${NAME}/current/Resources/usr/lib/x86_64-linux-gnu/gtk-3.0"
export LD_LIBRARY_PATH="/System/Libraries:/System/Libraries/Runtime/glibc:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64:/Programs/${NAME}/current/Libraries\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
exec "${LOADER}" \\
  --library-path "\${LD_LIBRARY_PATH}" \\
  "/Programs/${NAME}/current/Commands/${command_name}.real" "\$@"
EOF
  chmod 0755 "${PROGRAM}/Commands/${command_name}"
done

ln -sfn "/Programs/${NAME}/${SAFE_VERSION}" "${AUZIX_ROOT}/Programs/${NAME}/current"
for command_name in "${COMMANDS[@]}"; do
  ln -sfn "/Programs/${NAME}/current/Commands/${command_name}" "${RUNTIME_BIN}/${command_name}"
  ln -sfn "/Programs/${NAME}/current/Commands/${command_name}" "${RUNTIME_USR}/bin/${command_name}"
done

cat >"${RUNTIME_USR}/share/applications/auzix-${PACKAGE_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${NAME}
Exec=${PACKAGE_ID} %F
TryExec=${PACKAGE_ID}
Icon=${PACKAGE_ID}
Categories=${CATEGORIES}
Terminal=false
EOF

commands_json="$(
  printf '%s\n' "${COMMANDS[@]}" |
    jq -R --arg name "${NAME}" --arg version "${SAFE_VERSION}" \
      '"/Programs/" + $name + "/" + $version + "/Commands/" + .' |
    jq -s .
)"
exports_json="$(
  {
    printf '/System/Compatibility/usr/share/applications/auzix-%s.desktop\n' "${PACKAGE_ID}"
    for command_name in "${COMMANDS[@]}"; do
      printf '/System/Compatibility/bin/%s\n' "${command_name}"
      printf '/System/Compatibility/usr/bin/%s\n' "${command_name}"
    done
    for resource_dir in "${RESOURCE_DIRS[@]}"; do
      printf '/System/Compatibility/usr/share/%s\n' "${resource_dir}"
    done
  } | jq -R . | jq -s .
)"

jq -n \
  --arg name "${NAME}" \
  --arg version "${SAFE_VERSION}" \
  --arg source_package "${PACKAGE_ID}" \
  --arg prefix "/Programs/${NAME}/${SAFE_VERSION}" \
  --arg current "/Programs/${NAME}/current" \
  --arg libraries "/Programs/${NAME}/${SAFE_VERSION}/Libraries" \
  --arg loader "${LOADER}" \
  --argjson commands "${commands_json}" \
  --argjson exports "${exports_json}" \
  '{
    name: $name,
    version: $version,
    kind: "program",
    migration_stage: "stage-1-compat-install",
    prefix: $prefix,
    paths: {current: $current, libraries: $libraries},
    commands: $commands,
    runtime_libraries: [$libraries],
    compatibility_exports: $exports,
    source: {
      type: "debian-installed-closure",
      distribution: "debian",
      suite: "trixie",
      package: $source_package
    },
    validation: {loader: $loader, mode: "base-loader-app-private-libs"},
    notes: "First-class AuziX office package with app-private ELF dependencies, application resources, compatibility commands, and desktop integration. Core/security/desktop substrate libraries are provided by the AUZiX base release."
  }' >"${AUZIX_ROOT}/System/PackageDB/${NAME}-${SAFE_VERSION}.auzix.json"

for command_name in "${COMMANDS[@]}"; do
  validation_library_path="/System/Libraries:/System/Libraries/Runtime/glibc:${RUNTIME_USR}/lib/x86_64-linux-gnu:${AUZIX_ROOT}/System/Compatibility/lib/x86_64-linux-gnu:${AUZIX_ROOT}/System/Compatibility/lib64:${PROGRAM}/Libraries"
  LD_LIBRARY_PATH="${validation_library_path}" \
    "${AUZIX_ROOT}${LOADER}" \
    --library-path "${validation_library_path}" \
    "${PROGRAM}/Commands/${command_name}.real" --version >/dev/null 2>&1 ||
    [[ "${command_name}" != "${PACKAGE_ID}" ]]
done

log "${NAME} installed at ${PROGRAM}"
