#!/usr/bin/env bash
set -euo pipefail

AUZIX_ROOT="${1:?usage: build-auzix-command-suite-package.sh ROOT RECIPE}"
RECIPE="${2:?usage: build-auzix-command-suite-package.sh ROOT RECIPE}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/auzix-library-policy.sh"

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

command_extract_root="$(mktemp -d)"
cleanup_command_extract() {
  [[ -d "${command_extract_root}" && "${command_extract_root}" == /tmp/* ]] && rm -rf "${command_extract_root}"
}
trap cleanup_command_extract EXIT

copy_libraries() {
  local binary="$1"
  local dependency
  ldd "${binary}" 2>/dev/null |
    awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' |
    sort -u |
    while IFS= read -r dependency; do
      [[ -f "${dependency}" ]] || continue
      auzix_copy_app_private_library "${dependency}" "${libraries}/$(basename "${dependency}")"
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
  auzix_copy_app_private_library "${interpreter}" "${libraries}/$(basename "${interpreter}")"
  printf '%s\n' "$(basename "${interpreter}")"
}

while IFS=$'\t' read -r export_name host_command; do
  source_path="$(command -v "${host_command}" || true)"
  if [[ -z "${source_path}" ]]; then
    source_package="$(jq -r '.source.package // empty' "${RECIPE}")"
    if [[ -n "${source_package}" && "${source_package}" != "null" ]] &&
      command -v apt-get >/dev/null 2>&1 &&
      command -v dpkg-deb >/dev/null 2>&1; then
      package_deb_dir="${command_extract_root}/${export_name}/debs"
      package_extract_dir="${command_extract_root}/${export_name}/extract"
      mkdir -p "${package_deb_dir}" "${package_extract_dir}"
      if (cd "${package_deb_dir}" && apt-get download "${source_package}" >/dev/null) &&
        compgen -G "${package_deb_dir}/*.deb" >/dev/null; then
        for deb in "${package_deb_dir}"/*.deb; do
          dpkg-deb -x "${deb}" "${package_extract_dir}"
        done
        for candidate in \
          "${package_extract_dir}/usr/bin/${host_command}" \
          "${package_extract_dir}/bin/${host_command}" \
          "${package_extract_dir}/usr/sbin/${host_command}" \
          "${package_extract_dir}/sbin/${host_command}"; do
          [[ -x "${candidate}" ]] || continue
          source_path="${candidate}"
          break
        done
      fi
    fi
  fi
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
      --set-interpreter "/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2" \
      --set-rpath '/System/Libraries:/System/Libraries/Runtime/glibc:$ORIGIN/../Libraries:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64' \
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
export LD_LIBRARY_PATH="/System/Libraries:/System/Libraries/Runtime/glibc:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64:/Programs/${name}/current/Libraries\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
exec "/Programs/${name}/current/Commands/${export_name}.real" ${fixed_args} "\$@"
EOF
  else
cat >"${program}/Commands/${export_name}" <<EOF
#!/Programs/BusyBox/current/Commands/busybox sh
${environment}
${shell_prelude}
export LD_LIBRARY_PATH="/System/Libraries:/System/Libraries/Runtime/glibc:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64:/Programs/${name}/current/Libraries\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
exec "/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2" \\
  --library-path "\${LD_LIBRARY_PATH}" \\
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

program_abs="$(readlink -f "${program}")"
libraries_abs="$(readlink -f "${libraries}")"

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

busybox_chroot_path="/Programs/BusyBox/current/Commands/busybox"
[[ -x "${AUZIX_ROOT}${busybox_chroot_path}" ]] || {
  printf '%s: validation needs AUZiX BusyBox at %s; run auzix-strict-busybox first\n' "${name}" "${busybox_chroot_path}" >&2
  exit 1
}

glibc_loader_chroot_path="/System/Libraries/Runtime/glibc/ld-linux-x86-64.so.2"
[[ -x "${AUZIX_ROOT}${glibc_loader_chroot_path}" ]] || {
  printf '%s: validation needs AUZiX glibc loader at %s; run auzix-strict-dynprobe/core-runtime first\n' "${name}" "${glibc_loader_chroot_path}" >&2
  exit 1
}

validation_command_root="${AUZIX_ROOT}/System/Validation/CommandSuite/${name}"
cleanup_validation=()
cleanup() {
  local path
  for path in "${cleanup_validation[@]:-}"; do
    if [[ -d "${path}" && "${path}" == "${AUZIX_ROOT}/System/Validation/"* ]]; then
      rm -rf "${path}"
    fi
  done
}
trap cleanup EXIT

cleanup_validation+=("${validation_command_root}")
mkdir -p "${validation_command_root}"

while IFS= read -r command_name; do
  cat >"${validation_command_root}/${command_name}" <<EOF
#!${busybox_chroot_path} sh
exec "/Programs/${name}/current/Commands/${command_name}" "\$@"
EOF
  chmod 0755 "${validation_command_root}/${command_name}"
done < <(jq -r '.commands[].name' "${RECIPE}")

while IFS= read -r smoke_command; do
  smoke_script="${validation_command_root}/run-smoke.sh"
  cat >"${smoke_script}" <<EOF
set -e
export PATH="/System/Compatibility/bin:/System/Compatibility/sbin:/System/Compatibility/usr/bin:/System/Compatibility/usr/sbin:/Programs/BusyBox/current/Commands"
export AUZIX_COMMAND_ROOT="/System/Validation/CommandSuite/${name}"
export LD_LIBRARY_PATH="/System/Libraries:/System/Libraries/Runtime/glibc:/System/Compatibility/usr/lib/x86_64-linux-gnu:/System/Compatibility/lib/x86_64-linux-gnu:/System/Compatibility/lib64:/Programs/${name}/current/Libraries"
${smoke_command}
EOF
  chmod 0755 "${smoke_script}"
  chroot "${AUZIX_ROOT}" "${busybox_chroot_path}" sh "/System/Validation/CommandSuite/${name}/run-smoke.sh"
done < <(jq -r '.validation.smoke_commands[]' "${RECIPE}")
trap - EXIT
cleanup
cleanup_command_extract

printf '[command-suite] built %s %s\n' "${name}" "${version}"
