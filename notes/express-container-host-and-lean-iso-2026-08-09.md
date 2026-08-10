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
