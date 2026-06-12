#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUEUE_FILE="${ROOT_DIR}/packages/installer-ui.queue.json"

jq -e '
  .format == "auzix-package-build-queue-v1"
  and ([.batches[].id] | length == (unique | length))
  and all(.batches[].packages[];
    (.state == "planned" and (has("script") | not))
    or
    (.state == "ready" and (.script | test("^scripts/build-auzix-[a-z0-9-]+-package[.]sh$")))
  )
' "${QUEUE_FILE}" >/dev/null

ready_ids="$(jq -r '.batches[] | select(.id == "installer-ui-core") | .packages[] | select(.state == "ready") | .id' "${QUEUE_FILE}")"
for required in AuzixPackageTools AuzixInstaller Xorg Enlightenment Terminology LightDM; do
  grep -Fx "${required}" <<<"${ready_ids}" >/dev/null
done

planned_ids="$(jq -r '.batches[] | select(.id == "installer-ui-next") | .packages[] | select(.state == "planned") | .id' "${QUEUE_FILE}")"
for required in GCC Binutils Make PkgConfig Gtk3Runtime AuzixInstallerGtk AuzixInstallerEfl; do
  grep -Fx "${required}" <<<"${planned_ids}" >/dev/null
done

echo "AuziX package bot contract: PASS"
