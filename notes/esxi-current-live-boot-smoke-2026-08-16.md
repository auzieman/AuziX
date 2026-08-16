# AUZiX current-live ESXi boot smoke — 2026-08-16

Scope: keep ESXi ISO boot testing in the BKC pipeline lane instead of direct,
untracked console work.

## BKC runs

- `4f6d5f36-e5d7-4ba1-9bd5-5268a5f55979`
  - Failed usefully.
  - The boot stage executed but exposed a helper contract mismatch:
    `AUZIX_ISO_NAME` was expected as an environment variable while the live BKC
    executor was calling the helper with argv.
- `28dcf92d-89a9-46ca-bdc3-c367aa75a176`
  - Completed.
  - Executed `boot-desktop-iso-smoke` against
    `auzix-live-desktop-current-current-live-20260816T185556Z.iso` on ESXi VM
    `auzix-esxi-workstation-media-01`.
  - Serial evidence shows the ISO booted from ESXi CD media and reached the
    display path.
  - The run records `ssh tcp/22 not listening` as the remaining image-content
    blocker/warning.

## Pipeline/script fixes captured

- BKC commit `a855687` fixes ESXi CD media attachment by writing the absolute
  datastore path first, reloading the VM, and validating ESXi normalized the
  backing to `[datastore1] auzix-isos/<iso>`.
- BKC commit `2303c7d` lets the same helper run in two modes:
  - workstation/tunnel mode via `AUZIX_ISO_NAME` and SSH config;
  - direct ESXi mode via argv after BKC uploads the helper to the ESXi host.

## SSH observation

The built root contains OpenSSH, `/Services/ssh/run`, host keys, and
`/System/Settings/ssh/sshd_config`. A chroot service test reached bind-time,
which means the package is not simply missing.

The current StartSequence starts services in the background, then immediately
checks TCP/22. That can produce a false `not listening` receipt if sshd has not
settled yet. `scripts/add-auzix-live-tools.sh` now waits up to five seconds
before recording the SSH listen result.

Follow-up live capture after the operator observed the one-time Enlightenment
config dialog:

- ESXi VMID `13` was powered on.
- Serial showed DHCP address `10.20.0.113/24`.
- `vmwgfx` initialized and VMware VMMouse devices were detected.
- The display path started and reached the GUI.
- The process summary still showed no `sshd` process, so the SSH warning is not
  only the immediate `nc` probe. The service runner likely exits before the
  summary.

Build-root checks:

- `/Services/ssh/run`, OpenSSH binaries, host keys, and `sshd_config` exist.
- `chroot <AuzixRoot> /Services/ssh/run` reaches bind-time when the host port is
  already in use, proving the package can load and read its keys/config in
  chroot semantics.
- `ld-linux --list /Programs/OpenSSH/host/Commands/sshd` resolves OpenSSH's
  runtime libraries from `/System/Compatibility/lib*/...`.

Next source fix should make `StartSequence` include the failing service log tail
when a declared service is absent from the process summary, especially
`/System/Logs/ssh.log`.

Next ISO run should distinguish between a real sshd failure and a too-early
boot receipt.
