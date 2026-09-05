# AX-012/task65 — Debian D-Bus install observation result

September 5, 2026 15:46 PDT. Source `fea2a20a36333dbd7bd80dcc19d45f42dbe4aac1`.
Worker `apk-alpha-source-audit`, run `20260905-debian-install-trace`.
R730 output `/var/lib/auzix-build/package-proof/AX-012-source-fea2a20a3633`.
Log `/var/lib/auzix-build/receipts/apk-alpha-20260905-debian-install-trace-resume-fea2a20a3633.log`.
No mapping repair, APK, image, or VM change.

## Debian transaction (passed)

`apt-get --no-install-recommends install dbus=1.16.2-2` in disposable
`debian:trixie-slim` succeeded. Exact requested version; no substitution.

Configure order from `debian-dpkg.log`:

1. `adduser` (needed by system-bus-common when systemd-sysusers is absent)
2. libs / session-common / daemon bits
3. **`dbus-system-bus-common` configure** — creates `messagebus`
4. **`dbus` configure** — `dpkg-statoverride --update --add root messagebus 4754`
   on `/usr/lib/dbus-1.0/dbus-daemon-launch-helper`
5. `libc-bin` trigger

Observed effects (`debian-effects.log`):

- `messagebus:x:100:101::/nonexistent:/usr/sbin/nologin`
- helper `root:messagebus 4754` and matching statoverride
- sysusers snippet owned by `dbus-system-bus-common`
- **system bus socket absent after install** (slim container, no systemd)
- explicit `dbus-daemon --system --fork` then `ListNames` replied
  `org.freedesktop.DBus`

Fresh-install start policy in this container: Debian's generated
`invoke-rc.d` / `deb-systemd-invoke start` did not leave a socket. Upgrade
path is reload-only (`ReloadConfig`), never a system-bus restart. Do not
invent a restart from our mapper.

## AuziX intake on the same hash (still needs-review)

Retained archive `4161ceae23fe852bc4eaafe4e3441ac3df3a952affa2f832bef3f44e29494d06`
still reports 12 findings. Helper in the extracted payload remains
`root:root 0755`. `source_build_executed` and `maintainer_hooks_executed`
are false. The helper-permission component test passed again on a fixture
(`apk_install_tested=false`).

The mapper treats `dpkg-statoverride` as an unresolved donor protocol, and
only emits `install-configuration` for default/dbus and init.d. It does not
execute the observed account → permission → optional-start/reload order.
`DPKG_STATOVERRIDE_MODE_BLOCK` in `lifecycle_intake.py` matches a
versioned `chmod` form, not D-Bus's `--update --add root group 4754`.

## Next mapping work (not started)

Wire those observed operations, in order, into the existing D-Bus /
DBusSystemBusCommon adapters. Then install the emitted APK in an AuziX
root. Do not re-run this Debian observation. Do not touch VM145.
