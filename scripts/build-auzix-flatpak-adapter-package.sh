#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUZIX_ROOT_INPUT="${1:?usage: build-auzix-flatpak-adapter-package.sh ROOT RECIPE}"
RECIPE="${2:?usage: build-auzix-flatpak-adapter-package.sh ROOT RECIPE}"
mkdir -p "${AUZIX_ROOT_INPUT}"
AUZIX_ROOT="$(cd "${AUZIX_ROOT_INPUT}" && pwd)"

for command_name in jq install; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "${command_name}" >&2
    exit 1
  }
done

jq -e '
  .format == "auzix-flatpak-adapter-v1" and
  (.name | type == "string") and
  (.package_name | type == "string") and
  (.version | type == "string") and
  (.flatpak_ref | type == "string") and
  (.flatpak_command | type == "string") and
  (.commands | type == "array" and length > 0)
' "${RECIPE}" >/dev/null

name="$(jq -r '.name' "${RECIPE}")"
package_name="$(jq -r '.package_name' "${RECIPE}")"
version="$(jq -r '.version' "${RECIPE}")"
flatpak_ref="$(jq -r '.flatpak_ref' "${RECIPE}")"
flatpak_command="$(jq -r '.flatpak_command' "${RECIPE}")"
program="${AUZIX_ROOT}/Programs/${name}/${version}"
package_db="${AUZIX_ROOT}/System/PackageDB"

rm -rf "${AUZIX_ROOT}/Programs/${name}"
find "${package_db}" -maxdepth 1 -type f -name "${package_name}-*.auzix.json" -delete 2>/dev/null || true

mkdir -p "${program}/Commands" "${program}/Metadata" "${package_db}" \
  "${AUZIX_ROOT}/System/Compatibility/bin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/bin" \
  "${AUZIX_ROOT}/System/Compatibility/usr/share/applications"

while IFS=$'\t' read -r command_name description; do
  install -m 0755 /dev/stdin "${program}/Commands/${command_name}" <<EOF
#!/Programs/BusyBox/current/Commands/busybox sh
exec /Programs/Flatpak/current/Commands/flatpak run --command=${flatpak_command} ${flatpak_ref} "\$@"
EOF
  ln -sfn "/Programs/${name}/current/Commands/${command_name}" \
    "${AUZIX_ROOT}/System/Compatibility/bin/${command_name}"
  ln -sfn "/Programs/${name}/current/Commands/${command_name}" \
    "${AUZIX_ROOT}/System/Compatibility/usr/bin/${command_name}"
done < <(jq -r '.commands[] | [.name, (.description // "")] | @tsv' "${RECIPE}")

ln -sfn "/Programs/${name}/${version}" "${AUZIX_ROOT}/Programs/${name}/current"
cp "${RECIPE}" "${program}/Metadata/adapter.json"

if jq -e '.desktop? != null' "${RECIPE}" >/dev/null; then
  first_command="$(jq -r '.commands[0].name' "${RECIPE}")"
  desktop_id="$(jq -r '.flatpak_ref' "${RECIPE}")"
  desktop_path="${AUZIX_ROOT}/System/Compatibility/usr/share/applications/${desktop_id}.desktop"
  desktop_name="$(jq -r '.desktop.name // .name' "${RECIPE}")"
  generic_name="$(jq -r '.desktop.generic_name // ""' "${RECIPE}")"
  comment="$(jq -r '.desktop.comment // .description // ""' "${RECIPE}")"
  icon="$(jq -r '.desktop.icon // .flatpak_ref' "${RECIPE}")"
  terminal="$(jq -r 'if .desktop.terminal == true then "true" else "false" end' "${RECIPE}")"
  categories="$(jq -r '(.desktop.categories // ["Utility"]) | join(";") + ";"' "${RECIPE}")"
  mime_types="$(jq -r '(.desktop.mime_types // []) | if length > 0 then join(";") + ";" else "" end' "${RECIPE}")"
  {
    printf '[Desktop Entry]\n'
    printf 'Name=%s\n' "${desktop_name}"
    [[ -z "${generic_name}" ]] || printf 'GenericName=%s\n' "${generic_name}"
    [[ -z "${comment}" ]] || printf 'Comment=%s\n' "${comment}"
    printf 'Exec=/Programs/%s/current/Commands/%s %%U\n' "${name}" "${first_command}"
    printf 'Icon=%s\n' "${icon}"
    printf 'Terminal=%s\n' "${terminal}"
    printf 'Type=Application\n'
    printf 'Categories=%s\n' "${categories}"
    [[ -z "${mime_types}" ]] || printf 'MimeType=%s\n' "${mime_types}"
    printf 'X-AUZiX-Adapter=%s\n' "${package_name}"
    printf 'X-Flatpak=%s\n' "${flatpak_ref}"
  } >"${desktop_path}"
fi

jq \
  --arg package_name "${package_name}" \
  --arg version "${version}" \
  --arg prefix "/Programs/${name}/${version}" \
  --arg current "/Programs/${name}/current" \
  --arg flatpak_ref "${flatpak_ref}" \
  '{
    name: $package_name,
    version: $version,
    kind: "application-adapter",
    migration_stage: "flatpak-program-adapter-proof",
    description,
    prefix: $prefix,
    paths: {current: $current, metadata: ($prefix + "/Metadata/adapter.json")},
    flatpak_ref: $flatpak_ref,
    commands: [.commands[] | $prefix + "/Commands/" + .name],
    compatibility_exports: (
      ([.commands[].name as $command_name
        | "/System/Compatibility/bin/" + $command_name,
          "/System/Compatibility/usr/bin/" + $command_name
      ])
      + (if .desktop? then ["/System/Compatibility/usr/share/applications/" + .flatpak_ref + ".desktop"] else [] end)
    ),
    validation,
    source: {type: "flatpak", remote: "flathub", ref: $flatpak_ref},
    depends: (.depends // ["BusyBox", "Flatpak"]),
    notes: "Adapter only: the Flatpak app payload is managed by Flatpak under /System/State/flatpak."
  }' "${RECIPE}" >"${package_db}/${package_name}-${version}.auzix.json"

printf '[flatpak-adapter] built %s %s for %s\n' "${package_name}" "${version}" "${flatpak_ref}"
