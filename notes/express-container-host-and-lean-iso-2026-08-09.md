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
