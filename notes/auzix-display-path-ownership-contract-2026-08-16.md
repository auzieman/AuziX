# AUZiX display path + ownership contract — 2026-08-16

The ESXi live ISO input lockup exposed a broader display/session contract issue:
classic `/usr` aliases exist, but several startup surfaces were still treating
classic paths as primary locations.  That makes boot order and copied state
brittle when a payload is missing, staged late, or copied into a user home with
the wrong owner.

Rules:

1. AUZiX startup scripts must use `/System/Compatibility/usr/...` as the primary
   Debian compatibility path.
2. `/usr` may remain as an alias/fallback for software that hardcodes it, but
   AUZiX-authored scripts should not prefer it.
3. Shared package data remains `root:root` and non-writable by users:
   - `/System/Compatibility/usr/share/enlightenment`
   - `/System/Compatibility/usr/lib/x86_64-linux-gnu/enlightenment`
   - `/System/Compatibility/usr/share/fonts`
   - `/System/Compatibility/usr/share/X11`
4. Any shared data copied or generated into `/Users/auzix` becomes writable
   user state and must be `auzix:auzix` before launching E:
   - `/Users/auzix/.e`
   - `/Users/auzix/.elementary`
   - `/Users/auzix/.cache`
   - `/Users/auzix/.config`
   - `/Users/auzix/.local`
   - `/run/user/1000`
5. Xorg input must default to udev/libinput auto-add. Explicit `/dev/input/eventN`
   input config is fallback-only because VMware/QEMU event ordering changes.
6. Xorg package/stage must include the Debian surfaces X expects:
   - `/System/Compatibility/usr/lib/xorg/protocol.txt`
   - `/System/Compatibility/usr/share/X11/xorg.conf.d`
   - `/System/Compatibility/usr/share/X11/xkb`
   - `/System/Compatibility/usr/share/fonts/X11` when available
   - `/System/Compatibility/usr/share/fonts/truetype/dejavu`
7. Generated X configs should point at compatibility paths first:
   - `ModulePath /System/Drivers/Xorg/modules`
   - `ModulePath /System/Compatibility/usr/lib/xorg/modules`
   - `FontPath /System/Compatibility/usr/share/fonts/...`

Patches made:

- `scripts/build-auzix-host-xorg-package.sh`
  - staged `protocol.txt`
  - switched default input to auto-add/libinput
  - removed hardcoded event devices from default generated xorg.conf
  - added compatibility/native font path handling
- `scripts/add-auzix-live-tools.sh`
  - defaulted live Xorg input mode to auto
  - changed E session env to prefer `/System/Compatibility/usr`
  - changed config seeding to prefer `/System/Compatibility/usr/share/enlightenment`
- `scripts/stage-auzix-display-templates.sh`
  - changed E data dir default to `/System/Compatibility/usr/share/enlightenment`
- `scripts/repair-auzix-desktop-session.sh`
  - kept auto input path as primary repair behavior

Live-node hotfix notes:

- Current ESXi live node: `10.20.0.113`
- Current clean X/E state used auto-add/libinput and showed:
  - `AT Translated Set 2 keyboard` as keyboard
  - `VirtualPS/2 VMware VMMouse` as mouse
- Root-owned user state was corrected with:
  - `chown -R 1000:1000 /Users/auzix/.config /Users/auzix/.local /Users/auzix/.cache /Users/auzix/.e /Users/auzix/.elementary /run/user/1000`

Remaining cleanup:

- Remove classic `/usr` from candidate lists where it is not needed.
- Decide whether live ISO includes X11 bitmap fonts or trims those FontPath
  entries entirely.
- Decide whether to add systemd/elogind later; current `systemd-logind` warning
  is expected without that layer.

Bootstrap update — 2026-08-16:

8. `/System/Settings/auzix-paths.sh` is the canonical process bootstrap.
   It must be sourced before AUZiX-authored boot, display, installer, package,
   or launcher scripts invent PATH/LD/XDG/E variables locally.
9. A healthy shell/session must have a non-empty `LD_LIBRARY_PATH` with at least:
   - `/System/Compatibility/usr/lib/x86_64-linux-gnu`
   - `/System/Compatibility/lib/x86_64-linux-gnu`
   - `/System/Compatibility/lib64`
   - `/System/Libraries`
10. `/usr`, `/bin`, `/lib`, and friends are compatibility guard rails only.
    AUZiX-authored scripts should prefer `/System/Compatibility/...` and let the
    aliases catch upstream software that jumps the rails.
11. Package archives must preserve numeric owner, mode, setuid, setgid, sticky
    bits, and symlink targets.  The repo emitter now records a package metadata
    TSV beside each archive so this is auditable.
12. Package installation must extract with preserve-permissions (`tar -p` style)
    when running as root; otherwise good archives can still land broken.

Acceptance checks for the next ISO/repo run:

- `echo "$LD_LIBRARY_PATH"` from root SSH and desktop user session is non-empty.
- `/System/Boot/StartSequence`, `/System/Tools/start-e`,
  `/System/Tools/start-enlightenment-session`, and LightDM wrappers source
  `/System/Settings/auzix-paths.sh`.
- `scripts/validate-auzix-live-agent.sh` fails if that contract is missing.
- Repo package entries include `metadata.path` for archive ownership/mode audit.
