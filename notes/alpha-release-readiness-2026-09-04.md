# Alpha release readiness — September 4 review

Reviewed today's dialogue, Moon recovery and desktop launch notes, commits
through `237bafc`, current producers and BKC pipeline definitions. Read-only
R730 inspection confirmed the results below. This is a readiness audit, not a
new image or release receipt.

## Preserve the target

An installable AUZiX technology demo using APK, with the repaired E desktop,
working application launchers, branded theme/Foggy Trees, Midori and installer
autostart, SSH access, usable auzix sudo, Podman, APK package GUI/search and
Flatpak. The installed minimal target intentionally differs from the live
workstation. Retain the demonstrated office applications. The requested one
or two persistent Flatpak apps remain part of release acceptance.

Build on R730. Preserve the working VMs. Trace fixes into producers and retain
explicit source/image identities. Public promotion follows boot and install
validation.

## Today's repairs and remaining evidence

| Area | Recorded implementation | Remaining proof or gap |
| --- | --- | --- |
| E menus, XDG paths, launcher arguments | `c057e11`, desktop launch contract note | New package-installed root must preserve argv and public data roots; inspect visible menu and launch as auzix. |
| Terminal/PTY, E defaults | `a48283f`, Moon recovery note, boot/HDD generators | ServiceRuntime producer still lacks the same ptmx mapping. CLI version output does not prove a usable terminal. |
| LibreOffice | `c057e11` intake and UNO wrapper changes | Fresh source does not refresh retained archives. Validate Writer, Calc, Draw and Impress through menu and CLI, with persistent windows. |
| Python, adduser, diagnostics | Prior live tests and validation scripts | Repeat against the candidate; adduser version alone does not prove account creation. |
| SSH and sudo | `73878fd`, prior VM provisioning | Verify external login and sudo as auzix. Current final gate invokes sudo as root and is insufficient. |
| Flatpak | `e32bb70`, new RuntimeSupport package | Local smoke installs and removes a tiny app; no persistent graphical app is thereby included. Verify Flathub TLS, app installation, exports and launch. |
| Podman | `7092ace`, retained runtime APK closure | Version output is insufficient; test an actual container under the intended user. |
| Installer and package GUI | `0ae48e6`, `050bfa7`, `c67a166`, `73b7d6e` | EFL APK invocation exists. Package GUI search needs interaction testing. A real blank-disk install/reboot has not been established by these commits. |
| Runtime support APKs | `2d71b36`, `237bafc` | All three emitted; lifecycle execution and installed results remain unproved. |

## Observed build state

`/var/lib/auzix-build/package-proof/237bafc/apks` contains:

- `auzix-auzix-service-runtime-0.1.0-r0.apk`
- `auzix-auzix-desktop-integration-2026.08.09-r0.apk`
- `auzix-flatpak-runtime-support-0.1.0-r0.apk`

No emit-package/pre-HDD build process appeared in the explicit process check.
The full run log
`/var/lib/auzix-build/pre-hdd-apk/20260904-alpha-apk-r7.log` ends in Nginx
dependency resolution failure for libcurl4t64, zlib1g and ca-certificates.
`fb33b06` supplies the local repository but this audit has not rerun it.
Provider aliases and selected archive closure still require an APK solver
check; emitting new aliases does not retroactively change existing APKs.

## Concrete delivery gaps

1. The installer backend searches for `add-auzix-live-tools.sh` in a build
   checkout or `/System/Tools`. Its package does not deliver a self-contained
   root-preparation implementation. That helper requires gcc and sibling
   source inputs. Copying the script alone is insufficient. Reuse the existing
   generated payload through its package owner.
2. The backend still defaults jq to AuzixPackageTools and unconditionally
   calls `sync_live_runtime_contract` after root prep. That copies live state
   even when the earlier seed-copy option is disabled. Audit the intended
   minimal install against this existing implementation before using a disk.
3. ServiceRuntime's after-install is the mount command itself; its first
   argument is interpreted as a root directory. APK lifecycle invocation must
   not be treated as a boot service invocation. Verify the actual generated
   hook and move runtime mount execution to its existing service entrypoint.
4. DesktopIntegration activation copies older desktop defaults and requests
   an E restart. Merely adding this old producer does not establish today's
   launcher/session fixes; compare its payload before activation on a live VM.
5. Final-root checks lack a fully specified offline runtime/mount context and
   real auzix-user validation. Source-string checks are not GUI acceptance.

## Small corrections made during this audit

- HDD builder requires an explicit validated pre-HDD image instead of silently
  choosing the August 31 salvage tag.
- Invoke the final validator using sh (tracked mode is 100644), after creating
  `/run/sshd` for the offline check.
- Resolve final-validator file tests inside chroot so absolute AUZiX links
  cannot resolve against the build host; load the staged runtime environment
  for command probes.
- Installer fails when grub-install is absent, instead of reporting a
  successful GRUB installation without executing one.

Shell syntax, `git diff --check`, and `python3 -m auzix validate` pass
(70 packages, 7 profiles, 1 target). These checks do not prove runtime behavior.

## BKC release wiring

`BlackKnightController/pipelines/auzix-release-hdd-build-deploy/pipeline.json`
still points to the August package-profile flow, VM142 and
`scripts/build-validated-hdd.sh`. It is not yet the current alpha builder route.

`auzix-public-beta-shelf` provides the existing public host/TLS/promotion path,
but defaults to landing-only and old source locations. The referenced
`stage-auzix-public-beta-shelf.sh` discovers ISO files; HDD publication needs
explicit artifact mapping. APK index/signature delivery and client trust must
be checked against the actual public shelf before promotion.

## Next bounded sequence

Close the producer/hook and installer payload gaps above; solve and install
the selected APK set on R730; inspect the resulting filesystem and run user
checks; build from that explicit image identity; boot a test VM and validate
desktop/SSH/Flatpak/Podman; install onto a blank test disk and reboot it; then
use the existing BKC public path with explicit artifacts and verified APK
repository trust. Record distinct build, boot, install and publication results.
