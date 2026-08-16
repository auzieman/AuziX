# AUZiX Desktop Lifecycle Triage Contract

Purpose: collect enough live-host evidence from vmid135-style installs to
compare AUZiX state against the Debian/Trixie lifecycle fragments before
applying fixes.

This is not a repair script. It is the triage input for the fixer/reconcile
mode.

## Scope

Initial desktop lifecycle stack:

```text
DBus
Polkit
LightDM
PulseAudio
EFL / Efreet
Enlightenment
XDG portals
Flatpak
```

Reference evidence comes from:

```text
out/package-slices/*/auzix-fragments/*.auzix-fragment.json
out/pipeline-receipts/desktop-lifecycle-farming/*.summary.md
```

## Live-host collection

The triage collector should emit one JSON report, for example:

```text
/System/State/reports/desktop-lifecycle-triage.json
```

Minimum report sections:

### Host/session identity

- hostname, kernel, boot time;
- current user sessions;
- `DISPLAY`, `XDG_RUNTIME_DIR`, `XDG_DATA_DIRS`, `XDG_CONFIG_DIRS`,
  `DBUS_SESSION_BUS_ADDRESS`, `LD_LIBRARY_PATH`;
- user/group membership for `root`, `auzix`, `lightdm`, `messagebus`,
  `polkitd`, and service users when present.

### Runtime directories and permissions

- `/run`, `/run/dbus`, `/run/lightdm`, `/run/user/1000`, `/run/user/1000/bus`;
- `/System/Run` if used;
- `/System/State`, `/System/Cache`, `/System/Logs`;
- ownership/mode drift for user cache/config dirs:
  `/Users/auzix/.cache`, `.config`, `.local`, `.e`.

### DBus state

- system bus process and socket;
- session bus process and socket;
- visible service dirs:
  `/System/Settings/dbus-1`, `/System/Compatibility/usr/share/dbus-1`,
  package-exported DBus service dirs;
- `dbus-send` smoke for system and session bus where safe.

### Polkit state

- `polkitd` process if expected;
- policy dirs exported from packages;
- `pkcheck`/`pkaction` bounded smoke;
- `pkexec` mode/capability/setuid expectations.

### LightDM/X/session state

- LightDM process tree, greeter/session child;
- active Xorg process, command line, log path;
- session wrapper path and environment;
- PAM files and modes;
- Xorg config, input driver config, loaded modules;
- recent LightDM and Xorg errors.

### EFL / Efreet / Enlightenment state

- `efreetd` process owner and environment;
- `enlightenment` process owner and environment;
- E/EFL command availability:
  `efreetd`, `eina_btlog`, `enlightenment`, `enlightenment_start`,
  `enlightenment_remote`;
- Efreet cache dirs and ownership;
- E logs and recent backtraces;
- exact Enlightenment launcher failure logs for visible `.desktop` entries;
- XDG data dirs used by E and Efreet.

### PulseAudio/session audio state

- PulseAudio/PipeWire processes if expected;
- runtime socket under `/run/user/1000`;
- `/System/Settings/pulse` and package-exported config;
- `pactl info` bounded smoke;
- E mixer errors classified as missing audio service, not compositor failure.

### Desktop integration state

- `.desktop` files from package exports;
- menu files and desktop directories;
- icon/theme dirs;
- MIME database;
- GSettings schema dirs and compiled schemas;
- E menu cache and open-with state.

### Flatpak/portal state

- `flatpak --version`;
- system/user remotes;
- system helper DBus service availability;
- `xdg-dbus-proxy`, `bwrap`, portal services;
- `/var`/`/System/State` assumptions and compatibility aliases.

## Classification

Each issue should be classified as one of:

- `missing-package`;
- `missing-lifecycle-hook`;
- `wrong-owner-or-mode`;
- `missing-runtime-dir`;
- `missing-dbus-service`;
- `missing-polkit-policy`;
- `missing-service-manager-translation`;
- `missing-wrapper-runtime-ladder`;
- `wrong-path-alias`;
- `cache-not-refreshed`;
- `validation-probe-failed`;
- `unknown-needs-fragment`.

## Output shape

```json
{
  "format": "auzix-desktop-lifecycle-triage-v1",
  "host": "auzix-live",
  "generated_at": "...",
  "stack": "desktop-session",
  "observed": {},
  "expected_fragments": [],
  "issues": [
    {
      "id": "desktop.dri.example",
      "package": "ExamplePackage",
      "surface": "dbus",
      "classification": "missing-dbus-service",
      "expected": "...",
      "observed": "...",
      "suggested_lifecycle_action": "dbus.install-service"
    }
  ],
  "safe_to_reconcile": false
}
```

`safe_to_reconcile` is false when the triage collector sees conflicting
ownership, missing core packages, or a service manager transition that needs an
explicit operator decision.
