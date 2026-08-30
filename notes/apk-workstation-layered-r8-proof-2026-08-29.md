# APK workstation layered r8 proof — 2026-08-29

Builder: `r730-ai-01` through Docker context `bkc-auzix-r730`.

## Proven

- Factory image: `auzix/package-factory:lifecycle-r13-20260829`.
- Locked APK layer volume: `auzix-workstation-layered-r13-20260829`.
- Fresh root volume: `auzix-workstation-root-r8-layered-20260829`.
- The layer composer selected 488 unique APK filenames from base, office/Xorg,
  desktop shell, Flatpak, and current runtime/identity/library/OpenSSH overlays.
- Every selected artifact is recorded with source layer and SHA-256 in
  `layer-lock.json` inside the layer volume.
- Three bootstrap packages plus the locked layer installed in a single fresh
  AUZiX-root transaction. The transaction exited zero with 491 registered
  packages.
- APK's installed script database is non-empty (10240 bytes). BasePasswd,
  Passwd, Libselinux1, OpenSSH client, and OpenSSH server scripts visibly ran.
- Package-only effects passed: root and sshd identities, sshd configuration,
  three host keys, `/Services/ssh/run`, and `sshd -t`.
- CLI checks passed: OpenSSH 10.0p2, `ps auxw`, htop 3.4.1, Glances 4.3.1,
  BusyBox netstat/pkill, and Flatpak 1.16.1.
- Twelve desktop entries are published.

## Remaining failed assertions

- AbiWord: missing published `libebook-contacts-1.2.so.4`.
- LibreOffice Writer: missing published `librtmp.so.1`.
- LibreOffice Calc: missing published `libgobject-2.0.so.0`.
- No generated `mime.cache` or `icon-theme.cache` exists yet.
- Terminology payload is at `/Programs/Terminology/host`, but its expected
  `/Programs/Terminology/current` link is absent.
- Midori is not present in the inspected APK volumes and needs intake/build.
- Xorg command publication/runtime validation remains incomplete.

These are package/factory blockers. No external configuration or cache repair
script was used to manufacture a pass.

## Discarded evidence

- Installing AUZiX BusyBox into an Alpine host root is invalid because it
  replaces Alpine's shell/runtime.
- Root r4 was disposable and exposed that APK's deprecated broad `--force`
  enables broken-world pruning. Use the layer composer or narrowly scoped APK
  options instead.
- Root r7 installed most graphical payloads, but an unfiltered stale overlay
  caused 16 same-version path collisions. It is not acceptance evidence.
