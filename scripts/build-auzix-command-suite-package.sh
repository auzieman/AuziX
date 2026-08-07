#!/usr/bin/env bash
set -euo pipefail

AUZIX_ROOT="${1:?usage: build-auzix-command-suite-package.sh ROOT RECIPE}"
RECIPE="${2:?usage: build-auzix-command-suite-package.sh ROOT RECIPE}"

for command_name in jq install ldd patchelf readlink; do
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
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Compatibility/sbin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/bin" \
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
  environment="$(jq -r --arg name "${export_name}" '
    .commands[] | select(.name == $name) | (.environment // {})
    | to_entries[] | "export " + .key + "=" + (.value | @sh)
  ' "${RECIPE}")"
  shell_prelude="$(jq -r --arg name "${export_name}" '
    .commands[] | select(.name == $name) | (.shell_prelude // [])[]
  ' "${RECIPE}")"
cat >"${program}/Commands/${export_name}" <<EOF
#!/Programs/BusyBox/current/Commands/busybox sh
${environment}
${shell_prelude}
export LD_LIBRARY_PATH="/Programs/${name}/current/Libraries"
exec "/Programs/${name}/current/Commands/${export_name}.real" ${fixed_args} "\$@"
EOF
  chmod 0755 "${program}/Commands/${export_name}"
  ln -sfn "/Programs/${name}/current/Commands/${export_name}" \
    "${AUZIX_ROOT}/System/Compatibility/bin/${export_name}"
  ln -sfn "/Programs/${name}/current/Commands/${export_name}" \
    "${AUZIX_ROOT}/System/Compatibility/sbin/${export_name}"
  ln -sfn "/Programs/${name}/current/Commands/${export_name}" \
    "${AUZIX_ROOT}/System/Compatibility/usr/bin/${export_name}"
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
      "/System/Compatibility/bin/" + .,
      "/System/Compatibility/sbin/" + .,
      "/System/Compatibility/usr/bin/" + .,
      "/System/Compatibility/usr/sbin/" + .
    )),
    validation,
    source,
    depends: (.depends // ["BusyBox"]),
    notes: "First-pass command-suite repack. Graduate to an upstream source build before declaring the port native."
  }' "${RECIPE}" >"${package_db}/${name}-${version}.auzix.json"

while IFS= read -r smoke_command; do
  AUZIX_COMMAND_ROOT="${program}/Commands" \
  LD_LIBRARY_PATH="${libraries}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
    bash -o pipefail -ec "${smoke_command}"
done < <(jq -r '.validation.smoke_commands[]' "${RECIPE}")

while IFS= read -r export_name; do
  real_command="${program}/Commands/${export_name}.real"
  if interpreter="$(patchelf --print-interpreter "${real_command}" 2>/dev/null)"; then
    patchelf \
      --set-interpreter "/Programs/${name}/current/Libraries/$(basename "${interpreter}")" \
      "${real_command}"
  fi
done < <(jq -r '.commands[].name' "${RECIPE}")

printf '[command-suite] built %s %s\n' "${name}" "${version}"
