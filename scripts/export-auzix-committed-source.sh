#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
TARGET="${1:?usage: export-auzix-committed-source.sh TARGET_DIRECTORY}"
COMMIT="$(git -C "${ROOT_DIR}" rev-parse HEAD)"

[[ -z "$(git -C "${ROOT_DIR}" status --porcelain)" ]] || {
  printf 'Refusing to export a dirty AuziX checkout.\n' >&2
  exit 1
}

mkdir -p "${TARGET}"
rsync -a --delete \
  --exclude='.git/' \
  --exclude='out/' \
  --exclude='artifacts/' \
  --exclude='downloads/' \
  "${ROOT_DIR}/" "${TARGET}/"
printf '%s\n' "${COMMIT}" >"${TARGET}/.auzix-source-commit"
printf 'exported_commit=%s target=%s\n' "${COMMIT}" "${TARGET}"
