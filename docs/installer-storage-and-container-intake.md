# Guided storage and container package intake

## Storage scope

AuziX should borrow Debian Installer's recipe discipline without importing
Partman or its debconf policy engine. The graphical frontend remains a plan
producer; one privileged backend owns discovery, partitioning, formatting,
mounting, copy, fstab, bootloader, and receipts.

Offer only these reviewed choices initially:

1. **Simple whole disk** — the existing single ext4 root, retained as the
   recovery-safe baseline.
2. **Curated root/home** — GPT, a 512 MiB EFI system partition, an optional
   2 MiB BIOS-GRUB partition for hybrid media, ext4 root, and ext4 home using
   the reviewed percentage slider. Prefer a swap file after installation over
   another partition.
3. **Curated LVM root/home (experimental until boot-proven)** — the same boot
   partitions, one LVM PV, `auzix` VG, `root` and `home` LVs, and a swap file.
   Do not enable execution until the installed initramfs activates the VG and
   VM135 boots it repeatedly.

Advanced manual partitioning, encryption, RAID, multi-disk VGs, thin pools,
and custom mount-point editors remain deferred. GParted may be offered as an
explicit expert escape hatch, outside the guarded automatic recipe.

Every recipe must resolve to a concrete preview containing disk identity and
size, partition table, partitions/LVs, filesystems, mount points, boot mode,
and destructive target. Execution must rediscover the disk and reject a
changed identity or size.

## Backend prerequisites

- disk discovery with stable `/dev/disk/by-id` identity where available;
- GPT-capable partition tool (`parted` or `sfdisk`) and `partprobe`/udev wait;
- `e2fsprogs` and `dosfstools`;
- `lvm2` only for the experimental LVM recipe;
- installed-initramfs LVM activation and matching fstab/root arguments;
- UEFI and BIOS GRUB installation paths tested independently;
- cleanup traps that unmount target bind mounts and deactivate only the VG
  created by the current receipt.

## Repository-only container intake

Container packages are not live-ISO payloads. Build and publish them through a
separate repository lane before attempting an AuziX container-host smoke run.

### Common substrate

- CA certificates, curl, tar, gzip/xz/zstd;
- full OpenSSH client; server is optional and must own a `/Services` entry;
- uid/gid and subordinate-ID tooling;
- nftables/iptables integration and IP forwarding validation;
- overlayfs kernel proof plus `fuse-overlayfs` fallback;
- cgroups v2 mount and delegation receipt.

### Podman-first candidate set

- podman, conmon, crun or runc;
- containers-common and storage configuration;
- netavark plus aardvark-dns, or one explicitly selected CNI generation;
- slirp4netns or pasta and fuse-overlayfs;
- buildah and skopeo after the runtime smoke succeeds.

### Docker candidate set

- containerd and runc;
- Docker engine and CLI;
- network/firewall helpers and a packaged daemon service;
- BuildKit only after pull/run/network/volume tests pass.

Do not publish a stage-0 Debian extraction as ready merely because archive
installation succeeds. Each candidate needs AuziX commands, dependencies,
configuration ownership, services where applicable, and these smoke results:

1. version/help command;
2. pull a pinned small image by digest;
3. run and remove it;
4. outbound DNS and HTTPS;
5. bind mount and named volume;
6. restart daemon/runtime where applicable;
7. record cgroup, storage driver, network backend, and receipt paths.

## Current catalog evidence — 2026-08-06

The active ns1 repository currently exposes only `Debian.openssh-client` and
`Debian.openssh-server` from the container-oriented search set. Both are
`stage-0-fhs-build` and declare neither commands nor service exports. No
Docker, Podman, containerd, runc/crun, Buildah, Skopeo, fuse-overlayfs,
slirp4netns, LVM2, or partition-tool package is currently published.

The Ollama worker may evaluate deterministic failures after a build. Give it
the source metadata, recipe, build log, `ldd` output, receipt, and smoke log;
accept only a proposed recipe/contract patch. It must not trigger publication
or invent dependencies absent from package metadata and runtime evidence.
