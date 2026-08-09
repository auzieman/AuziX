#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX_PATH="${1:-${ROOT_DIR}/artifacts/auzix/repo/index.json}"
AUZIX_ROOT="${2:-${ROOT_DIR}/out/auzix-strict/AuzixRoot}"
OUTPUT_DIR="${3:-${ROOT_DIR}/out/libreoffice-slow-walk}"
SAMPLE_SPREADSHEET="${ROOT_DIR}/tests/fixtures/documents/auzix-libreoffice-calc-proof.ods"

mkdir -p "${OUTPUT_DIR}"

if [[ ! -s "${INDEX_PATH}" ]]; then
  printf 'missing repo index: %s\n' "${INDEX_PATH}" >&2
  exit 1
fi

closure_report="${OUTPUT_DIR}/closure-check.tsv"
wrapper_report="${OUTPUT_DIR}/wrapper-check.txt"
sample_report="${OUTPUT_DIR}/sample-document-check.txt"
headless_report="${OUTPUT_DIR}/headless-convert-check.txt"

python3 - "${INDEX_PATH}" >"${closure_report}" <<'PY'
import json
import sys

index_path = sys.argv[1]
with open(index_path, "r", encoding="utf-8") as handle:
    index = json.load(handle)

packages = {package["name"]: package for package in index.get("packages", [])}
roots = ["LibreOfficeCommon", "LibreOfficeCore", "LibreOfficeWriter", "LibreOfficeCalc"]

print("root\tclosure_count\tmissing_count\tmissing")
for root in roots:
    seen = set()
    missing = []
    stack = [root]
    while stack:
        name = stack.pop()
        if name in seen:
            continue
        seen.add(name)
        package = packages.get(name)
        if not package:
            missing.append(name)
            continue
        stack.extend(package.get("depends") or [])
    print(f"{root}\t{len(seen)}\t{len(missing)}\t{','.join(missing)}")
PY

mapfile -t wrappers < <(
  python3 - "${INDEX_PATH}" "${AUZIX_ROOT}" <<'PY'
import json
import sys

index_path, auzix_root = sys.argv[1], sys.argv[2]
with open(index_path, "r", encoding="utf-8") as handle:
    index = json.load(handle)

wanted = {
    "LibreOfficeCommon": {"loffice"},
    "LibreOfficeWriter": {"lowriter"},
    "LibreOfficeCalc": {"localc"},
}

for package in index.get("packages", []):
    names = wanted.get(package.get("name"))
    if not names:
        continue
    for command in package.get("commands") or []:
        if command.rsplit("/", 1)[-1] in names:
            print(f"{auzix_root}{command}")
PY
)

: >"${wrapper_report}"
for wrapper in "${wrappers[@]}"; do
  {
    printf 'WRAPPER\t%s\n' "${wrapper}"
    if [[ -f "${wrapper}" ]]; then
      sed -n '1,80p' "${wrapper}"
      if grep -F '$(\"${BB}\" basename' "${wrapper}" >/dev/null; then
        printf 'CHECK\tbad-escaped-busybox-basename\n'
      elif grep -F '$("${BB}" basename' "${wrapper}" >/dev/null; then
        printf 'CHECK\tbusybox-basename-ok\n'
      else
        printf 'CHECK\tbusybox-basename-pattern-missing\n'
      fi
    else
      printf 'CHECK\tmissing-wrapper\n'
    fi
    printf 'END_WRAPPER\t%s\n' "${wrapper}"
  } >>"${wrapper_report}"
done

{
  printf 'SAMPLE_SPREADSHEET\t%s\n' "${SAMPLE_SPREADSHEET}"
  if [[ -s "${SAMPLE_SPREADSHEET}" ]]; then
    file "${SAMPLE_SPREADSHEET}" || true
    if command -v unzip >/dev/null 2>&1; then
      unzip -t "${SAMPLE_SPREADSHEET}" || true
    else
      printf 'CHECK\tunzip-not-available\n'
    fi
  else
    printf 'CHECK\tmissing-sample-spreadsheet\n'
  fi
} >"${sample_report}"

{
  printf 'HEADLESS_CONVERT_SAMPLE\t%s\n' "${SAMPLE_SPREADSHEET}"
  convert_out="${OUTPUT_DIR}/headless-convert"
  mkdir -p "${convert_out}"

  chroot_sample="/System/State/libreoffice/auzix-libreoffice-calc-proof.ods"
  chroot_out="/System/State/libreoffice/headless-convert"
  localc_wrapper="/Programs/LibreOfficeCalc/current/Commands/localc"
  loffice_wrapper="/Programs/LibreOfficeCommon/current/Commands/loffice"
  soffice_program="/System/State/libreoffice/program/soffice"

  runner=""
  mkdir -p "${AUZIX_ROOT}/System/State/libreoffice/headless-convert"
  if [[ -s "${SAMPLE_SPREADSHEET}" ]]; then
    cp "${SAMPLE_SPREADSHEET}" "${AUZIX_ROOT}${chroot_sample}"
  fi

  if chroot "${AUZIX_ROOT}" /Programs/BusyBox/current/Commands/busybox test -x "${localc_wrapper}" 2>/dev/null; then
    runner="${localc_wrapper}"
  elif chroot "${AUZIX_ROOT}" /Programs/BusyBox/current/Commands/busybox test -x "${loffice_wrapper}" 2>/dev/null; then
    runner="${loffice_wrapper}"
  elif chroot "${AUZIX_ROOT}" /Programs/BusyBox/current/Commands/busybox test -x "${soffice_program}" 2>/dev/null; then
    runner="${soffice_program}"
  fi

  if [[ -z "${runner}" ]]; then
    printf 'CHECK\tmissing-headless-runner\n'
    printf 'CANDIDATE\t%s\n' "${localc_wrapper}"
    printf 'CANDIDATE\t%s\n' "${loffice_wrapper}"
    printf 'CANDIDATE\t%s\n' "${soffice_program}"
  elif [[ ! -s "${SAMPLE_SPREADSHEET}" ]]; then
    printf 'CHECK\tmissing-sample-spreadsheet\n'
  else
    printf 'RUNNER\t%s\n' "${runner}"
    printf 'COMMAND\tchroot %s %s --headless --convert-to csv --outdir %s %s\n' "${AUZIX_ROOT}" "${runner}" "${chroot_out}" "${chroot_sample}"
    set +e
    chroot "${AUZIX_ROOT}" "${runner}" --headless --convert-to csv --outdir "${chroot_out}" "${chroot_sample}"
    rc=$?
    set -e
    printf 'EXIT\t%s\n' "${rc}"
    find "${AUZIX_ROOT}${chroot_out}" -maxdepth 1 -type f -print | sort
    csv_path="$(find "${AUZIX_ROOT}${chroot_out}" -maxdepth 1 -type f -name '*.csv' -print -quit)"
    if [[ "${rc}" -eq 0 && -s "${csv_path:-}" ]]; then
      printf 'CHECK\theadless-convert-ok\n'
      printf 'CSV\t%s\n' "${csv_path}"
      sed -n '1,20p' "${csv_path}" || true
    else
      printf 'CHECK\theadless-convert-failed\n'
    fi
  fi
} >"${headless_report}" 2>&1

printf 'LibreOffice spine closure report: %s\n' "${closure_report}"
printf 'LibreOffice spine wrapper report: %s\n' "${wrapper_report}"
printf 'LibreOffice sample document report: %s\n' "${sample_report}"
printf 'LibreOffice headless convert report: %s\n' "${headless_report}"
