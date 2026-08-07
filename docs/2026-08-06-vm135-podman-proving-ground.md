# VM135 Podman Proving Ground

Date: 2026-08-06/07

## Outcome

AUZiX installed and executed its first native-path OCI host stack on VM135.
The public package repository supplied BusyBox, Conmon, Crun,
ContainersCommon, Netavark, AardvarkDNS, and Podman through `auzix-pkg`.

Validated evidence:

- `podman info --debug` resolves Conmon, Crun, Netavark, AardvarkDNS,
  seccomp, configuration, storage, runroot, and volumes through AUZiX paths;
- Docker archive import passes after preserving Podman's `/proc/self/exe`
  re-execution contract with an AUZiX ELF interpreter;
- `auzix/service:zero-busybox` executes on VM135;
- `auzix/service:one-nginx` runs as UID/GID 65534 and serves port 8080;
- upstream Alpine 3.24.1 pulls and executes;
- a 64 MiB ext4 image was created, loop-mounted, written, unmounted, and
  passed all `e2fsck` phases;
- rootless `podman info` passes with isolated user event, network, runtime,
  storage, and volume paths.

## Remaining Podman Gates

- Rootless image unpack needs `newuidmap`, `newgidmap`, and installed
  subordinate UID/GID ranges.
- Default bridge creation and `-p` publishing need bridge, veth, and netfilter
  modules in the active kernel's matching module package.
- The next ISO must align its kernel and module ABI and mount cgroup2 during
  startup. The boot tooling now contains the cgroup2 mount contract.

Host networking is proven. Default Netavark bridge networking is not yet
proven and must remain a release gate.

## Package Formula Lessons

- Receipts must own activation paths such as `/Programs/<Name>/current` and
  every compatibility export placed in an archive.
- Dynamic command suites use a strict AUZiX ELF interpreter plus an exact
  package-private `LD_LIBRARY_PATH`.
- Do not launch the dynamic loader as the process image for self-reexecuting
  programs: Podman uses `/proc/self/exe` for `storage-untar`.
- Rootful and rootless container state must never share locks, event logs,
  runroots, graphroots, network configuration, or volumes.
- Installed external application providers should project commands and
  metadata into `/Programs`, even when their deduplicated backing store lives
  under `/System/State`.

## Next Sequence

1. Build and boot an ABI-aligned kernel/module set with the container-host
   module gate enabled.
2. Validate Netavark bridge, DNS, outbound HTTP, and published Nginx port.
3. Port Uidmap and repeat rootless Alpine execution.
4. Start the minimal Flatpak lane: Bubblewrap, OSTree, xdg-dbus-proxy, Flatpak,
   then deliberate portal integration without Debian's full recommended set.
5. Project installed Flatpak applications as normal AUZiX program adapters,
   for example `/Programs/Firefox/current/Commands/firefox`.

## Evidence

- `docs/images/Screenshot at 2026-08-06 20-54-56.png`
- `out/source-workbench/extended-ports/oci-runtime.build.log`
- `out/source-workbench/extended-ports/oci-runtime.report.json`
- commits `a5e8d7c` and `72e7070`
