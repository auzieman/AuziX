# ESXi installer theme hotwire — 2026-08-16

Goal: test the new BlackKnight/Auzietek graphical installer look on the already
running ESXi AUZiX GUI ISO before committing to a full ISO rebuild.

## Build path used

Compiled on R730 / `lab-ai-worker` using the existing AUZiX builder image:

```sh
docker run --rm \
  -v /tmp/auzix-installer-hotwire:/work \
  -w /work \
  auzix/builder:lab \
  bash -lc 'gcc -D_GNU_SOURCE -O2 -Wall -Wextra -Werror \
    -o /work/auzix-installer-efl \
    installer/efl/auzix-installer-efl.c \
    $(pkg-config --cflags --libs elementary)'
```

Builder EFL reported:

```text
elementary 1.26.3
```

## Running guest

Target:

```text
ESXi AUZiX GUI ISO guest
IP: 10.20.0.113
SSH path: ssh -J lab-ns1 root@10.20.0.113
Display: :0
```

The guest had:

- `/System/Tools/launch-auzix-installer`
- `/Programs/AuzixInstaller`
- EFL runtime libraries under `/System/Compatibility/lib/x86_64-linux-gnu`

It did not already have:

- `/Programs/AuzixInstallerEfl/current/Commands/efl.real`

## Hotwired payload

Copied into the live guest:

```text
/Programs/AuzixInstallerEfl/0.1/Commands/efl.real
/Programs/AuzixInstallerEfl/0.1/Commands/efl
/Programs/AuzixInstallerEfl/0.1/Commands/launch-auzix-installer
/Programs/AuzixInstaller/current/Frontends/efl -> /Programs/AuzixInstallerEfl/current/Commands/efl
/System/Settings/installer/theme/installer-theme.json
/System/Settings/installer/theme/mark-shield-swords.png
/System/Settings/installer/theme/retro-boing-strip.png
```

The core launcher was hotwired to prefer EFL when `DISPLAY` is set:

```sh
AUZIX_INSTALLER_FRONTEND="${AUZIX_INSTALLER_FRONTEND:-efl}"
exec /System/Tools/auzix-installer-gui "$@"
```

## Runtime status

Launched into the running GUI session with:

```sh
DISPLAY=:0 AUZIX_INSTALLER_FRONTEND=efl /System/Tools/launch-auzix-installer
```

Observed process:

```text
/Programs/AuzixInstallerEfl/current/Commands/efl.real \
  --questions /System/Settings/installer/questions.json \
  --schema /System/Settings/installer/install-plan.schema.json
```

## Notes

- The live ISO is very lean: even `install` and `ln` were not in normal PATH, so
  hotwire used BusyBox for file operations.
- A direct SSH-side `efl.real --help` is not a valid smoke because the binary is
  graphical and waits without a display.
- Full validation must happen visually in the ESXi console:
  - shield appears;
  - dark installer opens;
  - `RUN PREFLIGHT` works;
  - `VALIDATE PLAN` writes the unconfirmed plan;
  - package/storage intent is preserved.

If the GUI hotwire fails visually, do not keep poking the live guest. Fold the
failure into the package/ISO build and run a full new ISO through the lab-build
pipeline.
