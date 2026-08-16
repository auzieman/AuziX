#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="${AUZIX_PUBLIC_REPO_DIR:-${1:-${ROOT_DIR}/artifacts/auzix/repo}}"
ISO_DIR="${AUZIX_PUBLIC_ISO_DIR:-${2:-${ROOT_DIR}/artifacts/auzix}}"
RECEIPT_DIR="${AUZIX_PUBLIC_RECEIPT_DIR:-${3:-${ROOT_DIR}/out}}"
SHELF_DIR="${AUZIX_PUBLIC_SHELF_DIR:-${4:-${ROOT_DIR}/public/auzix}}"
MAX_ISOS="${AUZIX_PUBLIC_MAX_ISOS:-3}"
MAX_RECEIPTS="${AUZIX_PUBLIC_MAX_RECEIPTS:-80}"
LANDING_ONLY="${AUZIX_PUBLIC_LANDING_ONLY:-0}"
SHOWCASE_IMAGE="${AUZIX_PUBLIC_SHOWCASE_IMAGE:-${ROOT_DIR}/docs/images/Screenshot at 2026-08-16 11-45-57.png}"
SHOWCASE_IMAGE_NAME="auzix-installer-desktop-20260816.png"
FIELD_NOTE_VIDEO_URL="https://www.youtube.com/watch?v=vkrk-H5vc_U&t=303s"

log() {
  printf '[auzix-public-shelf] %s\n' "$*" >&2
}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    log "missing command: $1"
    exit 1
  }
}

require date
require find
require jq
if [[ "${LANDING_ONLY}" != "1" ]]; then
  require rsync
  require sha256sum
fi

mkdir -p "${SHELF_DIR}/repo" "${SHELF_DIR}/isos" "${SHELF_DIR}/receipts" "${SHELF_DIR}/assets"

if [[ -f "${SHOWCASE_IMAGE}" ]]; then
  install -m 0644 "${SHOWCASE_IMAGE}" "${SHELF_DIR}/assets/${SHOWCASE_IMAGE_NAME}"
else
  log "showcase image not found: ${SHOWCASE_IMAGE}"
fi

package_count=0
iso_count=0
receipt_count=0
artifact_status="pending-next-iso-install-proof"
repo_path=""

if [[ "${LANDING_ONLY}" == "1" ]]; then
  jq -n \
    '{format: "auzix-repo-placeholder-v1", status: "pending-next-iso-install-proof", packages: []}' \
    >"${SHELF_DIR}/repo/index.json"
  printf 'AUZiX package repository publication is pending the next ISO/install validation.\n' \
    >"${SHELF_DIR}/repo/README.txt"
  printf 'AUZiX ISO publication is pending the next ISO/install validation.\n' \
    >"${SHELF_DIR}/isos/README.txt"
  printf 'AUZiX public receipts are pending the next ISO/install validation.\n' \
    >"${SHELF_DIR}/receipts/README.txt"
  repo_path="repo/index.json"
else
  [[ -f "${REPO_DIR}/index.json" ]] || {
    log "missing AUZiX repo index: ${REPO_DIR}/index.json"
    exit 1
  }

  jq -e '.format == "auzix-repo-v1" and (.packages | type == "array")' \
    "${REPO_DIR}/index.json" >/dev/null

  rsync -a "${REPO_DIR}/" "${SHELF_DIR}/repo/"

  while IFS= read -r iso_path; do
    iso_name="$(basename "${iso_path}")"
    case "${iso_name}" in
      *public*|*beta*|*live-demo*|*themefix*|*installer*)
        install -m 0644 "${iso_path}" "${SHELF_DIR}/isos/${iso_name}"
        if [[ -f "${iso_path}.sha256" ]]; then
          install -m 0644 "${iso_path}.sha256" "${SHELF_DIR}/isos/${iso_name}.sha256"
        else
          sha256sum "${SHELF_DIR}/isos/${iso_name}" >"${SHELF_DIR}/isos/${iso_name}.sha256"
        fi
        iso_count=$((iso_count + 1))
        ;;
    esac
    [[ "${iso_count}" -ge "${MAX_ISOS}" ]] && break
  done < <(find "${ISO_DIR}" -maxdepth 2 -type f -name '*.iso' -printf '%T@ %p\n' | sort -nr | awk '{sub(/^[^ ]+ /, ""); print}')

  while IFS= read -r receipt_path; do
    receipt_name="$(basename "${receipt_path}")"
    install -m 0644 "${receipt_path}" "${SHELF_DIR}/receipts/${receipt_name}"
    receipt_count=$((receipt_count + 1))
    [[ "${receipt_count}" -ge "${MAX_RECEIPTS}" ]] && break
  done < <(find "${RECEIPT_DIR}" -maxdepth 4 -type f \
    \( -name '*auzix*.json' -o -name '*auzix*.txt' -o -name '*auzix*.summary' -o -name '*repository-publish.report.json' \) \
    -printf '%T@ %p\n' | sort -nr | awk '{sub(/^[^ ]+ /, ""); print}')

  package_count="$(jq '.packages | length' "${SHELF_DIR}/repo/index.json")"
  artifact_status="staged"
  repo_path="repo/index.json"
fi
build_commit="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
published_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -n \
  --arg format "auzix-public-beta-shelf-v1" \
  --arg published_at "${published_at}" \
  --arg build_commit "${build_commit}" \
  --arg repo_path "${repo_path}" \
  --arg artifact_status "${artifact_status}" \
  --argjson package_count "${package_count}" \
  --argjson iso_count "${iso_count}" \
  '{
    format: $format,
    generated_at: $published_at,
    source_commit: $build_commit,
    artifact_status: $artifact_status,
    repo_index: $repo_path,
    package_count: $package_count,
    iso_count: $iso_count,
    paths: {
      repo: "repo/",
      isos: "isos/",
      receipts: "receipts/"
    }
  }' >"${SHELF_DIR}/manifest.json"

cat >"${SHELF_DIR}/index.html.next" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>AUZiX Beta</title>
  <style>
    :root { color-scheme: dark; font-family: system-ui, sans-serif; background: #071019; color: #f3fbff; }
    body { margin: 0; min-height: 100vh; background: radial-gradient(circle at 20% 0%, #183a5b 0, transparent 38%), #071019; }
    main { max-width: 920px; margin: 0 auto; padding: 8vh 24px; }
    h1 { font-size: clamp(2.4rem, 7vw, 5.5rem); margin: 0 0 .25em; letter-spacing: .03em; }
    .tag { color: #7be7ff; text-transform: uppercase; letter-spacing: .22em; font-weight: 700; }
    nav { display: flex; flex-wrap: wrap; gap: 10px; margin: 26px 0; }
    nav a { border: 1px solid #24506d; border-radius: 999px; padding: 8px 13px; background: rgba(10, 35, 52, .7); text-decoration: none; }
    .card { border: 1px solid #24506d; background: rgba(4, 12, 20, .72); border-radius: 18px; padding: 22px; margin: 20px 0; box-shadow: 0 20px 60px rgba(0,0,0,.35); }
    .showcase { display: grid; grid-template-columns: minmax(0, 1fr) minmax(280px, .9fr); gap: 20px; align-items: center; }
    .showcase img { width: 100%; border-radius: 16px; border: 1px solid rgba(123,231,255,.26); box-shadow: 0 22px 70px rgba(0,0,0,.45); }
    .pill-row { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 18px; }
    .pill-row a { border: 1px solid #24506d; border-radius: 999px; padding: 9px 14px; background: rgba(10, 35, 52, .72); font-weight: 750; text-decoration: none; }
    a { color: #88e8ff; }
    code { background: #0b2233; padding: .15em .35em; border-radius: 6px; }
    ul { line-height: 1.7; }
    @media (max-width: 760px) { .showcase { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
  <main>
    <p class="tag">Auzietek Labs</p>
    <h1>AUZiX Beta</h1>
    <p>A small, stubbornly personal Linux-shaped operating system experiment:
    strict AUZiX paths, Enlightenment desktop, package factory, Podman proofs,
    and tiny containers that keep making people blink twice.</p>
    <nav aria-label="AUZiX links">
      <a href="/">AUZiX Home</a>
      <a href="repo/">Package Repo</a>
      <a href="isos/">ISOs</a>
      <a href="receipts/">Receipts</a>
      <a href="https://auzietek.com/" target="_blank" rel="noopener noreferrer">Auzietek</a>
      <a href="https://linux-users.auzietek.com/blog" target="_blank" rel="noopener noreferrer">Linux Users</a>
      <a href="https://retro-users.auzietek.com/blog" target="_blank" rel="noopener noreferrer">Retro Users</a>
      <a href="https://www.blackknightcontroller.com/" target="_blank" rel="noopener noreferrer">BlackKnightController</a>
      <a href="https://discord.gg/zZh9XuDt9" target="_blank" rel="noopener noreferrer">Community</a>
      <a href="https://www.linkedin.com/in/auzieman" target="_blank" rel="noopener noreferrer">LinkedIn</a>
    </nav>
    <section class="card showcase">
      <div>
        <h2>Latest lab proof</h2>
        <p>The current public run shows the AUZiX installer, Enlightenment desktop,
        AUZiX path work, Midori rendering Auzietek, and the package-driven
        workstation direction coming together in one screen.</p>
        <div class="pill-row">
          <a href="${FIELD_NOTE_VIDEO_URL}" target="_blank" rel="noopener noreferrer">Watch the field note</a>
          <a href="assets/${SHOWCASE_IMAGE_NAME}" target="_blank" rel="noopener noreferrer">Open screenshot</a>
        </div>
      </div>
      <a href="assets/${SHOWCASE_IMAGE_NAME}" target="_blank" rel="noopener noreferrer">
        <img src="assets/${SHOWCASE_IMAGE_NAME}" alt="AUZiX installer and desktop running with Midori on the Auzietek site">
      </a>
    </section>
    <section class="card">
      <h2>Downloads</h2>
      <ul>
        <li><a href="repo/index.json">Package repository index</a> (${package_count} packages; ${artifact_status})</li>
        <li><a href="isos/">ISO candidates</a> (${iso_count} staged; ${artifact_status})</li>
        <li><a href="receipts/">Build receipts and validation notes</a> (${receipt_count} staged; ${artifact_status})</li>
        <li><a href="manifest.json">Publication manifest</a></li>
      </ul>
    </section>
    <section class="card">
      <h2>Beta notes</h2>
      <p>This shelf is generated from lab-built artifacts after public-safety
      checks. Public ISOs must not include lab SSH keys, password hashes,
      private URLs, or internal BKC addresses.</p>
      <p>Generated <code>${published_at}</code> from AUZiX commit
      <code>${build_commit}</code>.</p>
    </section>
    <section class="card">
      <h2>Community</h2>
      <p>Start at <a href="https://auzietek.com/" target="_blank" rel="noopener noreferrer">Auzietek</a> or the
      <a href="https://linux-users.auzietek.com/blog" target="_blank" rel="noopener noreferrer">Linux Users field notes</a>.
      Join the <a href="https://discord.gg/zZh9XuDt9" target="_blank" rel="noopener noreferrer">Auzietek community</a>,
      or use <a href="https://discord.com/channels/1537817201380302952/1537821223222780006" target="_blank" rel="noopener noreferrer">the Discord channel</a>
      if you are already inside. Professional contact is on
      <a href="https://www.linkedin.com/in/auzieman" target="_blank" rel="noopener noreferrer">LinkedIn</a>.</p>
    </section>
  </main>
</body>
</html>
HTML
mv -f "${SHELF_DIR}/index.html.next" "${SHELF_DIR}/index.html"

log "staged public beta shelf at ${SHELF_DIR}"
log "packages=${package_count} isos=${iso_count} receipts=${receipt_count}"
