# AUZiX package cleanup contract — 2026-08-14

The VM135 desktop regressions were not one-off launcher bugs. The root issue was
package lifecycle fidelity:

- archive creation must preserve numeric owner/group and modes by default;
- Debian payload metadata (`dpkg-deb -c`, control dir, md5sums, maintainer
  scripts) must be kept beside AUZiX receipts;
- package install/finalize must export the surfaces desktop software expects:
  `.desktop` files, DBus session and system services, DBus policy, GSettings
  schemas, `/usr/libexec` helpers, and compatibility library symlinks;
- E menus should come from the XDG `.desktop` + menu/efreet path, as on Trixie
  VMID132, not from hand-spawned duplicate launchers;
- unvalidated launchers stay `NoDisplay=true` until their command wrapper passes
  runtime checks (`ldd`, direct exec, and E log probe);
- BusyBox applets must be symlinked into the compatibility command path so a
  thin shell never loses basics such as `ls`, `cat`, `grep`, `sed`, `awk`,
  `df`, or `du`.

The repo builder default is `AUZIX_PACKAGE_NORMALIZE_OWNERS=0`. Flipping it to
`1` is an emergency/debug mode only; it intentionally loses package ownership
semantics and must be paired with explicit permission restoration metadata.

Near-term cleanup target:

1. rebuild or repack packages that still launch but glitch/die;
2. publish only packages whose receipts expose dependency/runtime ladders;
3. install through `auzix-pkg` so `finalize-installed-root` runs after each
   transaction;
4. compare VMID135 failures against VMID132 with `dpkg -S`, `dpkg -s`, `lsof`,
   E logs, and package maintainer fragments before adding AUZiX-specific logic.

VMID135 cleanup notes from 2026-08-15:

- `/Programs/Coreutils/current/Commands` was empty on the live workstation, so
  `/System/Compatibility/bin/id`, `ls`, `df`, and `du` were broken. The
  immediate rescue was to point missing basic applets at
  `/Programs/BusyBox/current/Commands/busybox`. Package activation should do
  this deterministically until native Coreutils is valid.
- Duplicate `auzix-demo-*.desktop` files existed in both
  `/System/Compatibility/usr/share/applications` and
  `/Users/auzix/.local/share/applications`. The user copies were moved aside
  under `/Users/auzix/.local/share/applications.disabled-auzix-dupes-*`; the
  canonical menu source should be the system XDG application directory unless a
  user intentionally overrides it.
- A stale `l3afpad` process was left running through the giant AUZiX loader
  path even after the launcher had been quarantined. The package/menu contract
  should keep unvalidated desktop entries hidden until their wrapper can pass a
  direct runtime probe.
- `su` initially failed because `libpam_misc.so.0` was installed under
  `Libpam0g` but not surfaced into the compatibility library path. After that
  was linked, `su - auzix` still aborted, showing that PAM service files and
  security modules must be surfaced as a set, not one library at a time.
- Flatpak's `org.freedesktop.Flatpak.SystemHelper.service` and
  `flatpak-system-helper` existed under the Flatpak package RootFS but were not
  visible under the compatibility DBus/libexec surfaces. Package activation
  must expose DBus system-services/session-services/policy and libexec helpers.
- Flatpak app metadata is a useful native-port guidebook, not just a deployment
  format. VM135 showed Firefox, Zed, VSCodium, and LibreOffice Flatpaks entering
  their runtimes while native/app launchers still failed. Their metadata exposes
  the missing AUZiX contract directly: session bus names, system bus names,
  sockets (`fallback-x11`, `wayland`, `pulseaudio`, `ssh-auth`, `cups`), devices
  (`dri`/`all`), filesystem expectations, and app-specific environment such as
  LibreOffice's `GIO_EXTRA_MODULES`, `JAVA_HOME`, and `LIBO_FLATPAK`. Treat
  installed Flatpak metadata as another source of package lifecycle fragments.

VMID135 Flatpak/Kmod findings from 2026-08-15:

- `Kmod` was available in the repo but not installed on VMID135. After install,
  the payload contained Debian's `/usr/sbin/modprobe`, but AUZiX had only
  exported the `kmod` command. The Debian intake builder must publish executable
  `*/sbin/*` payloads through `/Programs/<Name>/current/Commands` and the
  compatibility `sbin`/`usr/sbin` paths, not only `bin`/`usr/bin`.
- DBus-activated helpers such as `/usr/libexec/flatpak-portal` execute directly
  from service files and do not enter normal AUZiX command wrappers. Raw
  symlinks caused `flatpak-portal` to fail on `libostree-1.so.1`. Activation
  must publish executable `usr/libexec` payloads as AUZiX wrappers that export
  compatibility library/data paths before execing the package-owned helper.
- With libexec wrappers in place, Flatpak shell smokes for Zed and Firefox
  reached the app runtime (`zed-shell-ok`, `firefox-shell-ok`) but still warned
  on the document portal.
- `/dev/fuse` existed, `Fuse3`/`Libfuse34` were installed, and `Kmod` could run
  `modprobe`, but `KernelModules-6.1.0-52-amd64` had `modules.dep` entries for
  `kernel/fs/fuse/fuse.ko` without the actual module file. This is a package
  validation failure: a kernel module package must not preserve dependency
  indexes that reference omitted module payloads.
- `KernelModules` now needs `fuse`/`cuse`/`virtiofs` in the desktop/container
  host set, and must hard-fail if `fuse.ko` is missing when Flatpak/Podman
  support is selected.
- VMID135's live `auzix-pkg` still used the older `record_install` path that
  passed large package JSON through `jq --argjson`. `Ephoto` exposed the bug:
  its dependency list is large and includes nullable entries, so the install
  appeared to hang while silently walking dependency state. The package-tools
  contract now records from a slurped temp file and ignores blank/null deps.
- `Ephoto` installed and launched on VMID135 once dependency recursion was
  bypassed for the already-installed dependency set. It is usable but noisy
  under the current EFL theme (`Dimensions.edj` fixed-part warnings), so EFL
  theme validation belongs in the desktop polish lane.
- `Gzip` is a real package/build target for the workstation/debug set. VMID135
  could create/extract plain tar archives but `tar -z` failed because `gzip`
  was not available in the compatibility command path.
- Flathub `Shotwell` and `Clementine` installed and launched on VMID135.
  `ClementineFlatpakAdapter` was already packaged; `ShotwellFlatpakAdapter`
  was added after the run. Until the FUSE/document-portal fix lands, Flatpak
  apps may need explicit `flatpak override --filesystem=/Users/auzix ...` so
  sandboxed apps see AUZiX's `/Users` home tree.
- `Zed`, VSCodium, and other editor Flatpaks now fail at a clearer boundary:
  the document portal cannot mount `/run/user/1000/doc` because the current
  kernel-module package cannot load `fuse`. Do not keep rebuilding editor
  adapters for this symptom; fix `KernelModules` coherence first.
