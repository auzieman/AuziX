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
package_self_reexec_direct="$(jq -r '.self_reexec_direct // false' "${RECIPE}")"
if [[ "${package_self_reexec_direct}" == "true" ]]; then
  for command_name in patchelf readelf; do
    command -v "${command_name}" >/dev/null 2>&1 || {
      printf 'Missing required command for self_reexec_direct recipe: %s\n' "${command_name}" >&2
      exit 1
    }
  done
fi
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

copy_interpreter() {
  local binary="$1"
  local interpreter
  interpreter="$(
    readelf -l "${binary}" 2>/dev/null |
      sed -n 's#.*Requesting program interpreter: \(.*\)]#\1#p' |
      head -1
  )"
  [[ -n "${interpreter}" && -f "${interpreter}" ]] || return 0
  install -m 0755 "${interpreter}" "${libraries}/$(basename "${interpreter}")"
  printf '%s\n' "$(basename "${interpreter}")"
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
  loader_name=""
  command_self_reexec_direct="$(jq -r --arg name "${export_name}" '
    .commands[] | select(.name == $name) | (.self_reexec_direct // empty)
  ' "${RECIPE}")"
  patch_elf="$(jq -r --arg name "${export_name}" '
    .commands[] | select(.name == $name) | (.patch_elf // empty)
  ' "${RECIPE}")"
  if [[ "${patch_elf:-$(jq -r '.patch_elf // false' "${RECIPE}")}" == "true" ]]; then
    loader_name="$(copy_interpreter "${source_path}")"
    [[ -n "${loader_name}" ]] || {
      printf '%s: cannot locate ELF interpreter for patch_elf command: %s\n' "${name}" "${source_path}" >&2
      exit 1
    }
    patchelf \
      --set-interpreter "/Programs/${name}/current/Libraries/${loader_name}" \
      --set-rpath '$ORIGIN/../Libraries' \
      "${program}/Commands/${export_name}.real"
  fi
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
if [[ "${command_self_reexec_direct:-${package_self_reexec_direct}}" == "true" ]]; then
cat >"${program}/Commands/${export_name}" <<EOF
#!/Programs/BusyBox/current/Commands/busybox sh
${environment}
${shell_prelude}
export LD_LIBRARY_PATH="/Programs/${name}/current/Libraries\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
exec "/Programs/${name}/current/Commands/${export_name}.real" ${fixed_args} "\$@"
EOF
  else
cat >"${program}/Commands/${export_name}" <<EOF
#!/Programs/BusyBox/current/Commands/busybox sh
${environment}
${shell_prelude}
exec "/Programs/${name}/current/Libraries/ld-linux-x86-64.so.2" \\
  --library-path "/Programs/${name}/current/Libraries" \\
  "/Programs/${name}/current/Commands/${export_name}.real" ${fixed_args} "\$@"
EOF
  fi
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
    launch_contract: {
      self_reexec_direct: (.self_reexec_direct // false),
      patch_elf: (.patch_elf // false),
      rpath: (if (.patch_elf // false) then "$ORIGIN/../Libraries" else null end)
    },
    notes: "First-pass command-suite repack. Graduate to an upstream source build before declaring the port native."
  }' "${RECIPE}" >"${package_db}/${name}-${version}.auzix.json"

while IFS= read -r smoke_command; do
  temp_program_link=""
  temp_busybox_link=""
  if [[ ! -e /Programs/BusyBox/current/Commands/busybox ]]; then
    busybox_path=""
    for candidate in \
      "${AUZIX_ROOT}"/Programs/BusyBox/*/Commands/busybox \
      "$(command -v busybox || true)"; do
      [[ -n "${candidate}" && -x "${candidate}" ]] || continue
      busybox_path="${candidate}"
      break
    done
    if [[ -n "${busybox_path}" ]]; then
      mkdir -p /Programs/BusyBox/current/Commands
      ln -sfn "${busybox_path}" /Programs/BusyBox/current/Commands/busybox
      temp_busybox_link=/Programs/BusyBox/current/Commands/busybox
    else
      printf '%s: validation needs busybox for AUZiX wrapper shebangs\n' "${name}" >&2
      exit 1
    fi
  fi
  if [[ "${program}" == "${AUZIX_ROOT}/Programs/"* && ! -e "/Programs/${name}/current" ]]; then
    if mkdir -p "/Programs/${name}" 2>/dev/null; then
      ln -sfn "${program}" "/Programs/${name}/current"
      temp_program_link="/Programs/${name}/current"
    else
      printf '%s: cannot create temporary /Programs/%s/current validation link; run builder as root or validate in a chroot\n' "${name}" "${name}" >&2
      exit 1
    fi
  fi
  AUZIX_COMMAND_ROOT="${program}/Commands" \
  LD_LIBRARY_PATH="${libraries}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
    bash -o pipefail -ec "${smoke_command}"
  if [[ -n "${temp_program_link}" ]]; then
    rm -f "${temp_program_link}"
  fi
  if [[ -n "${temp_busybox_link}" ]]; then
    rm -f "${temp_busybox_link}"
  fi
done < <(jq -r '.validation.smoke_commands[]' "${RECIPE}")

printf '[command-suite] built %s %s\n' "${name}" "${version}"
