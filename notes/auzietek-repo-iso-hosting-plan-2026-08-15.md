# Auzietek AUZiX repo / ISO hosting plan — 2026-08-15

Context: Auzietek has enough storage to host AUZiX repository and ISO artifacts
as they become ready. Use it as a distribution shelf, not as the build authority.

2026-08-15 storage note: the Auzietek/IONOS hosts were observed with roughly
200 GiB free each, enough for the current AUZiX package repository, ISO current
pointer, timestamped snapshots, and receipt shelves.

## Authority split

- `lab-build` remains the AUZiX build master.
- ns1 remains the lab publication surface:
  - `/mnt/ns1/AuziX/src`
  - `/mnt/ns1/AuziX/build-receipts`
  - `/srv/http/auzix/repo`
- Auzietek should mirror blessed outputs:
  - package repo snapshots
  - current package repo
  - ISO artifacts
  - `.sha256` files
  - build receipts / validation reports

## Proposed public layout

```text
/auzix/
  repo/
    current/
      index.json
      packages/
    snapshots/
      2026-08-15T....Z/
        index.json
        packages/
  iso/
    current/
      auzix-....iso
      auzix-....iso.sha256
    archive/
      2026/
        08/
          auzix-....iso
          auzix-....iso.sha256
  receipts/
    iso/
    packages/
  index.html
```

## Header / link bar

The public AUZiX shelf should have a small Auzietek/AUZiX header rather than a
plain directory listing. Suggested top links:

- AUZiX Home / Downloads: `/auzix/`
- Current ISO: `/auzix/iso/current/`
- Package Repo: `/auzix/repo/current/`
- Build Receipts: `/auzix/receipts/`
- Auzietek: `https://auzietek.com/`
- Linux Users lane: `https://linux-users.auzietek.com/blog`
- Retro Users lane: `https://retro-users.auzietek.com/blog`
- BlackKnightController: `https://blackknightcontroller.com/blog?lane=blackknight`
- Community: link to the Auzietek Community/Contact page. Discord details are
  available from Auzietek contact notes, but should be mediated there rather
  than raw-blasted into every repo/ISO artifact header.
- LinkedIn: `https://www.linkedin.com/in/auzieman`

Canonical contact/social source should be the Auzietek site/content checkout.
Current local file is `/home/auzieman/Projects/auzietek/contatc_us.md`
(`contact_us.md` intended spelling). It currently lists:

- Discord invite: `https://discord.gg/zZh9XuDt9`
- Discord channel: `https://discord.com/channels/1537817201380302952/1537821223222780006`
- LinkedIn: `https://www.linkedin.com/in/auzieman`

The publish job should read Discord, LinkedIn, email/contact form, and community
wording from that contact source rather than duplicating social/contact metadata
in the AUZiX repo. For Discord specifically, prefer a controlled
Community/Contact landing link over raw invite links in the AUZiX repo/ISO
artifact header.

## Community link rule

Use a stable human label in AUZiX public surfaces:

- preferred label: `Community`
- acceptable expanded label: `Auzietek Community`
- avoid labels like `Discord #auzietek` until the public channel naming and
  URL behavior are confirmed

The Auzietek Community/Contact page should handle the Discord wrinkle:

- new visitors use the invite link,
- existing members can use the direct channel link,
- Discord may require login or the desktop/mobile app,
- LinkedIn can remain a direct public profile link.

This keeps downloadable artifacts, repo indexes, and generated package/ISO pages
stable even if Discord invite/channel details change later.

Keep the header simple and durable: title, one-line description, latest ISO
card, repo card, and community/social links. This can be static HTML generated
by the publish pipeline.

## Mirror rule

Do not use destructive sync for the public ISO/archive mirror. No `--delete`
for ISO archive or receipts.

For `/repo/current`, destructive sync is acceptable only after:

1. local repo index validates,
2. every indexed package checksum matches,
3. a timestamped snapshot is written first.

## Pipeline shape

1. Build packages/ISO on `lab-build`.
2. Publish to ns1/lab repo.
3. Validate repo index and ISO checksum from the served URL.
4. Create an Auzietek timestamped snapshot.
5. Update Auzietek `current`.
6. Write a small `index.html` with:
   - latest ISO
   - SHA256
   - repo URL
   - package count
   - build receipt links

## Installer integration

Future installer UI should expose the selected repository URL and index checksum
before install. For lab demos, default to lab/ns1. For public/offsite installs,
default to the Auzietek mirror once it is validated.
