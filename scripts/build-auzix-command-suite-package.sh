#!/usr/bin/env bash
set -euo pipefail

AUZIX_ROOT="${1:?usage: build-auzix-command-suite-package.sh ROOT RECIPE}"
RECIPE="${2:?usage: build-auzix-command-suite-package.sh ROOT RECIPE}"

for command_name in jq install ldd readlink; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "${command_name}" >&2
    exit 1
  }
done

jq -e '
  .format == "auzix-command-suite-v1" and
  (.name | type == "string") and
  (.version | type == "string") and
  (.commands | type == "array" and length > 0)
' "${RECIPE}" >/dev/null

name="$(jq -r '.name' "${RECIPE}")"
version="$(jq -r '.version' "${RECIPE}")"
if [[ "${version}" == "auto" ]]; then
  source_package="$(jq -r '.source.package' "${RECIPE}")"
  version="$(dpkg-query -W -f='${Version}' "${source_package}")"
fi
program="${AUZIX_ROOT}/Programs/${name}/${version}"
libraries="${program}/Libraries"
package_db="${AUZIX_ROOT}/System/PackageDB"

mkdir -p "${program}/Commands" "${libraries}" "${package_db}" \
  "${AUZIX_ROOT}/System/Compatibility/sbin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/sbin"

copy_libraries() {
  local binary="$1"
  local dependency
  ldd "${binary}" 2>/dev/null |
    awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' |
    sort -u |
    while IFS= read -r dependency; do
      [[ -f "${dependency}" ]] || continue
      install -m 0755 "${dependency}" "${libraries}/$(basename "${dependency}")"
    done
}

while IFS=$'\t' read -r export_name host_command; do
  source_path="$(command -v "${host_command}" || true)"
  [[ -n "${source_path}" ]] || {
    printf '%s: command not found: %s\n' "${name}" "${host_command}" >&2
    exit 1
  }
  source_path="$(readlink -f "${source_path}")"
  install -m 0755 "${source_path}" "${program}/Commands/${export_name}.real"
  copy_libraries "${source_path}"
  fixed_args="$(jq -r --arg name "${export_name}" '
    .commands[] | select(.name == $name) | (.fixed_args // []) | map(@sh) | join(" ")
  ' "${RECIPE}")"
cat >"${program}/Commands/${export_name}" <<EOF
#!/bin/sh
exec "/Programs/${name}/current/Libraries/ld-linux-x86-64.so.2" \
  --library-path "/Programs/${name}/current/Libraries" \
  "/Programs/${name}/current/Commands/${export_name}.real" ${fixed_args} "\$@"
EOF
  chmod 0755 "${program}/Commands/${export_name}"
  ln -sfn "/Programs/${name}/current/Commands/${export_name}" \
    "${AUZIX_ROOT}/System/Compatibility/sbin/${export_name}"
  ln -sfn "/Programs/${name}/current/Commands/${export_name}" \
    "${AUZIX_ROOT}/System/Compatibility/usr/sbin/${export_name}"
done < <(jq -r '.commands[] | [.name, .host_command] | @tsv' "${RECIPE}")

ln -sfn "/Programs/${name}/${version}" "${AUZIX_ROOT}/Programs/${name}/current"

jq \
  --arg version "${version}" \
  --arg prefix "/Programs/${name}/${version}" \
  --arg current "/Programs/${name}/current" \
  --arg libraries "/Programs/${name}/${version}/Libraries" \
  '{
    name,
    version: $version,
    kind: "system",
    migration_stage: "first-pass-debian-repack",
    description,
    prefix: $prefix,
    paths: {current: $current, libraries: $libraries},
    commands: [.commands[] | $prefix + "/Commands/" + .name],
    compatibility_exports: ([.commands[].name] | map(
      "/System/Compatibility/sbin/" + .,
      "/System/Compatibility/usr/sbin/" + .
    )),
    validation,
    source,
    notes: "First-pass command-suite repack. Graduate to an upstream source build before declaring the port native."
  }' "${RECIPE}" >"${package_db}/${name}-${version}.auzix.json"

while IFS= read -r smoke_command; do
  AUZIX_COMMAND_ROOT="${program}/Commands" \
  LD_LIBRARY_PATH="${libraries}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
    bash -o pipefail -ec "${smoke_command}"
done < <(jq -r '.validation.smoke_commands[]' "${RECIPE}")

printf '[command-suite] built %s %s\n' "${name}" "${version}"
