#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUEUE_FILE="${ROOT_DIR}/packages/installer-ui.queue.json"
SOURCE_CATALOG="${ROOT_DIR}/packages/installer-ui.sources.json"
ENLIGHTENMENT_BUILDER="${ROOT_DIR}/scripts/build-auzix-host-enlightenment-package.sh"

jq -e '
  .format == "auzix-package-build-queue-v1"
  and ([.batches[].id] | length == (unique | length))
  and all(.batches[].packages[];
    (.state == "planned" and (has("script") | not))
    or
    (.state == "ready" and (.script | test("^scripts/build-auzix-[a-z0-9-]+-package[.]sh$")))
  )
' "${QUEUE_FILE}" >/dev/null

jq -e '
  .format == "auzix-package-source-catalog-v1"
  and ([.packages[].id] | length == (unique | length))
  and all(.packages[];
    (.build.script | test("^scripts/build-auzix-[a-z0-9-]+-package[.]sh$"))
    and (.recipe.receipt_glob | endswith(".auzix.json"))
    and (
      .source.type != "debian-packages"
      or ((.source.packages | type == "array") and (.source.packages | length > 0))
    )
  )
' "${SOURCE_CATALOG}" >/dev/null

ready_ids="$(jq -r '.batches[] | select(.id == "installer-ui-core") | .packages[] | select(.state == "ready") | .id' "${QUEUE_FILE}")"
for required in AuzixPackageTools AuzixInstaller Xorg Enlightenment Terminology LightDM; do
  grep -Fx "${required}" <<<"${ready_ids}" >/dev/null
  queue_script="$(jq -r --arg id "${required}" '
    .batches[].packages[] | select(.id == $id) | .script
  ' "${QUEUE_FILE}")"
  catalog_script="$(jq -r --arg id "${required}" '
    .packages[] | select(.id == $id) | .build.script
  ' "${SOURCE_CATALOG}")"
  [[ "${queue_script}" == "${catalog_script}" ]]
done

planned_ids="$(jq -r '.batches[] | select(.id == "installer-ui-next") | .packages[] | select(.state == "planned") | .id' "${QUEUE_FILE}")"
for required in GCC Binutils Make PkgConfig Gtk3Runtime AuzixInstallerGtk AuzixInstallerEfl; do
  grep -Fx "${required}" <<<"${planned_ids}" >/dev/null
done

[[ "$(grep -c 'cp -f --remove-destination' "${ENLIGHTENMENT_BUILDER}")" -ge 2 ]]
grep -F '"compatibility_exports": ["/System/Compatibility/bin/lua"]' \
  "${ROOT_DIR}/scripts/build-auzix-installer-package.sh" >/dev/null
grep -F '"compatibility_exports": ["/System/Compatibility/bin/dialog"]' \
  "${ROOT_DIR}/scripts/build-auzix-installer-package.sh" >/dev/null
grep -F '"/System/Tools/auzix-installer-gui"' \
  "${ROOT_DIR}/scripts/build-auzix-installer-package.sh" >/dev/null

echo "AuziX package bot contract: PASS"
