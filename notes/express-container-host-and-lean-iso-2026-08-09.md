# AUZiX express container-host and lean ISO notes — 2026-08-09

## Goal

Use the R730/lab-build container lane to turn the latest lessons into package
contracts before touching vmid135 again. Treat vmid135 as disposable until a
fresh install path is cleaner.

## Lessons from the failed live Podman repair

- `AuzixServiceRuntime` already owns the correct runtime mount contract:
  `/proc`, `/sys`, `/dev`, `/dev/pts`, `/dev/shm`, `/run`, and cgroup v2 at
  `/sys/fs/cgroup`.
- Podman is not a normal command-suite wrapper target. It self-reexecs through
  `/proc/self/exe` for operations such as storage extraction/import. If AUZiX
  launches the dynamic loader as the process image, Podman can later reexec the
  loader instead of Podman and fail in strange ways.
- The package builder needs an opt-in direct-exec contract:
  - copy the binary as `Commands/podman.real`;
  - make the visible `podman` command wrapper exec `podman.real` directly after
    AUZiX environment setup.
- A first attempt to patch Podman with a `/Programs/Podman/current/Libraries`
  interpreter and `$ORIGIN/../Libraries` rpath still segfaulted in the Trixie
  builder. Do not promote Podman to a pure patched-ELF contract yet.
- Express-lane decision: preserve direct exec for Podman self-reexec safety, but
  keep the loader/compatibility substrate as known technical debt until the
  patched-ELF failure is understood.
- The Podman package dependency declaration must include the actual container
  host helper layer, not only `podman`, `conmon`, `crun`, `netavark`, and
  `aardvark-dns`.

## Container-host package lane

The `Podman` contract now explicitly depends on:

- `AuzixServiceRuntime`
- `Conmon`
- `Crun`
- `ContainersCommon`
- `Netavark`
- `AardvarkDNS`
- `Fuse3`
- `Libfuse34`
- `FuseOverlayFS`
- `Uidmap`
- `Libsubid5`
- `Slirp4netns`
- `Pasta`
- `Libseccomp2`
- `Libgpgme11t64`
- `Libsqlite30`
- `Libcap2`
- `Libcap2Bin`

Known missing or still-to-build packages before declaring container host done:

- `FuseOverlayFS`
- `Slirp4netns`
- `Pasta` / `passt`

Validation gates should be real container operations, not only version checks:

1. `podman --version`
2. `podman info`
3. `podman load` or `podman import` from a known local Docker archive
4. `podman run` for an AUZiX BusyBox image
5. `podman run` for the AUZiX Nginx service image
6. HTTP probe against the Nginx container

## Lean ISO direction

The next ISO should be installer-spine media, not a desktop demo DVD:

- boot substrate;
- BusyBox shell;
- `auzix-pkg` and repo config;
- SSH access;
- CA bundle;
- disk tools: ext2/3/4, FAT, partitioning, mount tools;
- network basics;
- sudo/users/groups;
- service-runtime mounts;
- enough debug commands to install package groups over SSH.

Desktop, office, Flatpak, Podman demos, wallpapers, screenshots, and large
themes should move to packages/package groups. Add compatibility slash links
only as break-fix debt, not as the target contract.

## Registry/DNS note

The working intended image reference is:

`bkc-registry.lab.auzietek.com/auzix/service:one-nginx`

Both Trixie vmid132 and AUZiX vmid135 saw DNS failure for
`bkc-registry.lab.auzietek.com`. Before relying on pulls in demos or CI, fix the
registry DNS/hosts/pipeline inventory path.

## VM135 express ISO boot — 2026-08-09 evening

Artifact booted:

`/mnt/ns1/AuziX/src/artifacts/auzix/auzix-netinstall-express-20260810T020717Z.iso`

Proxmox copy:

`/var/lib/vz/template/iso/auzix-netinstall-express-vm135.iso`

SHA-256:

`9c6ef3d4dbad481ef0ff9399f0d7fa46f74c1fd695890780f72b5c5e075528f5`

VM135 was recreated as disposable cattle with a fresh 32 GiB `local-lvm` disk,
ISO-first boot order, and virtio network on `vmbr0`.

Result:

- PASS: Proxmox started VM135 from the new ISO.
- PASS: QMP screenshot confirmed the graphical installer/session reached the
  `Language` screen at 1920x1080.
- FAIL/SEAM: language selector list was empty and `Next` was disabled.
- FAIL/SEAM: no IPv4 DHCP lease or SSH was observed within the first boot
  window; only the VM's IPv6 link-local neighbor appeared on `vmbr0`.
- FAIL/SEAM: switching to TTY2 produced only a blank cursor, suggesting getty or
  emergency shell access is not yet staged for this live media path.

Next patch target:

- stage a default locale/language option so the installer can advance;
- start network/SSH independently of the graphical installer gate;
- add a live debug/getty console or serial console for headless recovery;
- keep post-boot reconstruction package-driven once the installer shell/network
  is reachable.

## VM135 installer-spine r4 — 2026-08-09 evening

Good checkpoint:

- Commit `1946469` made live ISO GUI autostart selectable.
- Commit `7988faf` passed live ISO mode flags into the r730 builder container.
- r4 was built with `AUZIX_DISPLAY_AUTOSTART=manual`.
- Worker proof before boot: `/System/Settings/display/autostart` contained
  `manual`.

Artifact:

`/mnt/ns1/AuziX/src/artifacts/auzix/auzix-netinstall-express-r4-20260810T024318Z.iso`

SHA-256:

`ad7027fa1fd4807781ba7a8875be1412c6f9dde6c569d4fe469d27162d79017a`

VM135 boot/install result:

- PASS: VM135 booted r4 without entering the frozen Enlightenment language
  wizard.
- PASS: live console showed `gui: autostart disabled`.
- PASS: DHCP succeeded on `eth0` with `192.168.1.198/24`.
- PASS: SSH as root succeeded at `192.168.1.198`.
- PASS: `auzix-installer validate` passed.
- PASS: corrected install plan for `/dev/sda` validated and executed.
- PASS: installed root booted disk-first from `/dev/sda1`.
- PASS: installed root mounted `/dev/sda1` as `/` and exposed SSH.
- PASS: `auzix-pkg refresh` pulled the NS1 repo index and saw `1180 packages`.
- PASS: Podman installed post-boot and `podman info` worked with:
  - cgroup v2;
  - `crun`;
  - `netavark`;
  - `aardvark-dns`;
  - graph root `/Work/Containers/storage`;
  - storage config `/System/Settings/containers/storage.conf`.

Remaining seams:

- The installer fell back from ext4 to ext2 because ext4 tooling is still not
  in the live installer spine.
- Installed hostname still reports `auzix-live`; identity finalization needs to
  apply the install plan hostname.
- LightDM hydration failed because repo metadata/package inventory references
  `LibpamSystemd`, which is not currently in the repository.
- E/LightDM should stay post-install package work until the theme/font/config
  stack is rebuilt cleanly; the ISO should remain shell/TUI-first.
- Early service status may report SSH not listening before it is fully up; add
  a delayed or socket-level check to reduce false negatives.

Next package/build targets:

1. Add ext4/e2fs tooling to the installer spine so VM installs format ext4.
2. Add or map `LibpamSystemd`, or adjust the LightDM dependency contract to the
   AUZiX logind/session provider actually used.
3. Add package-group/meta packages such as `AuzixDesktopBase` and
   `AuzixContainerHost`; the installer already records those selected names,
   but the repo currently exposes the component packages rather than those
   metas.
4. Rebuild E/LightDM as post-install packages with fonts/themes/config
   validation, not as a live ISO gate.
