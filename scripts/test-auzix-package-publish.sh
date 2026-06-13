#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

REPO_DIR="${TMP_DIR}/repo"
PUBLISH_DIR="${TMP_DIR}/published"
mkdir -p "${REPO_DIR}/packages"
printf 'package-data\n' >"${REPO_DIR}/packages/Test-1.auzix.tar.gz"
printf 'legacy-data\n' >"${REPO_DIR}/packages/Legacy-1.auzix.tar.gz"
sha="$(sha256sum "${REPO_DIR}/packages/Test-1.auzix.tar.gz" | awk '{print $1}')"
legacy_sha="$(sha256sum "${REPO_DIR}/packages/Legacy-1.auzix.tar.gz" | awk '{print $1}')"
jq -n --arg sha "${sha}" --arg legacy_sha "${legacy_sha}" '{
  format: "auzix-repo-v1",
  packages: [
    {
      name: "Test",
      version: "1",
      package: "Test-1.auzix.tar.gz",
      sha256: $sha,
      size: 13
    },
    {
      name: "Legacy",
      version: "1",
      package: "Legacy-1.auzix.tar.gz",
      sha256: $legacy_sha,
      size: 12
    }
  ]
}' >"${REPO_DIR}/index.json"

"${ROOT_DIR}/scripts/publish-auzix-package-repo.sh" "${REPO_DIR}" "${PUBLISH_DIR}"
jq -e '.format == "auzix-repo-v1" and (.packages | length == 2)' \
  "${PUBLISH_DIR}/index.json" >/dev/null
test -f "${PUBLISH_DIR}/packages/Test-1.auzix.tar.gz"
test -f "${PUBLISH_DIR}/packages/Legacy-1.auzix.tar.gz"

SECOND_REPO_DIR="${TMP_DIR}/repo-second"
mkdir -p "${SECOND_REPO_DIR}/packages"
printf 'replacement-data\n' >"${SECOND_REPO_DIR}/packages/Test-2.auzix.tar.gz"
printf 'additional-data\n' >"${SECOND_REPO_DIR}/packages/Additional-1.auzix.tar.gz"
replacement_sha="$(sha256sum "${SECOND_REPO_DIR}/packages/Test-2.auzix.tar.gz" | awk '{print $1}')"
additional_sha="$(sha256sum "${SECOND_REPO_DIR}/packages/Additional-1.auzix.tar.gz" | awk '{print $1}')"
jq -n \
  --arg replacement_sha "${replacement_sha}" \
  --arg additional_sha "${additional_sha}" \
  '{
    format: "auzix-repo-v1",
    packages: [
      {
        name: "Test",
        version: "2",
        package: "Test-2.auzix.tar.gz",
        sha256: $replacement_sha,
        size: 17
      },
      {
        name: "Additional",
        version: "1",
        package: "Additional-1.auzix.tar.gz",
        sha256: $additional_sha,
        size: 16
      }
    ]
  }' >"${SECOND_REPO_DIR}/index.json"

"${ROOT_DIR}/scripts/publish-auzix-package-repo.sh" "${SECOND_REPO_DIR}" "${PUBLISH_DIR}"
jq -e '
  (.packages | length == 3)
  and any(.packages[]; .name == "Test" and .version == "2")
  and any(.packages[]; .name == "Additional")
  and any(.packages[]; .name == "Legacy")
' "${PUBLISH_DIR}/index.json" >/dev/null
test ! -f "${PUBLISH_DIR}/packages/Test-1.auzix.tar.gz"
test -f "${PUBLISH_DIR}/packages/Test-2.auzix.tar.gz"
test -f "${PUBLISH_DIR}/packages/Additional-1.auzix.tar.gz"
test -f "${PUBLISH_DIR}/packages/Legacy-1.auzix.tar.gz"

echo "AuziX package publish contract: PASS"
