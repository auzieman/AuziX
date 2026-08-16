# VM135 demo containers and Office launcher pass - 2026-08-15

## Container demo state

- Rebuilt AUZiX service images on lab-build from the existing service-container script.
- Loaded both images into VM135 rootful Podman:
  - `localhost/auzix/service:zero-busybox` (~2.3 MB)
  - `localhost/auzix/service:one-nginx` (~15.5 MB)
- Replaced the Docker Hub nginx demo container with the native AUZiX Nginx image:
  - `auzix-native-nginx-demo`
  - URL: `http://127.0.0.1:8080/`
  - Probe text: `AUZiX container one`
- Added a persistent BusyBox proof container:
  - `auzix-busybox-zero-demo`
  - image: `localhost/auzix/service:zero-busybox`
- Existing supporting demo containers remain:
  - `auzix-python-demo`
  - `auzix-portainer`

## Desktop launcher labels

Restored AUZiX demo launchers with explicit provenance labels:

- `Writer (native)`
- `Calc (native)`
- `Impress (native)`
- `Draw (native)`
- `Midori (native)`
- `Pluma (native)`
- `LibreOffice (pak)`
- `Firefox (pak)`
- `Zed (pak)`

The old `auzix-demo-*` launchers were moved out of the active E menu cache.

## LibreOffice native wrapper finding

`Libicu76` was installed, but Writer and Calc failed with:

```text
libicuuc.so.76: cannot open shared object file
```

The package wrapper collected `runtime_packages`, but the Writer/Calc wrapper path did not include each runtime package's `RootFS` library directories in the final `LD_LIBRARY_PATH`.

Applied live VM135 hotfix during triage:

- For every runtime package root, add:
  - `usr/lib/x86_64-linux-gnu`
  - `lib/x86_64-linux-gnu`
  - `usr/lib`
  - `lib`
- Include `${runtime_lib_path}` in the final `LD_LIBRARY_PATH`.

Patched source template:

- `scripts/build-auzix-debian-intake-package.sh`

Important correction:

- A wrapper or `soffice.bin` process staying alive is not proof that the app
  painted in Enlightenment.
- The package maintainer proof must be one of:
  - visible E/X window evidence;
  - a successful headless command with useful output, such as `--version` or a
    document conversion;
  - an E launcher test that records no `.e-log.log` or `.xsession-errors`
    failure for the launched command.
- Do not continue live-editing VM135 wrappers as a root/admin workaround.
  Restore package-owned files from the package repo/artifact, then fix the
  package build contract and reinstall.

Rollback note:

- Later live experiments introduced `/System/Compatibility/bin/auzix-libreoffice`
  and a composed `/System/State/libreoffice` tree. Those were disabled/rolled
  back after they made native Office worse.
- The correct maintainer task is to rebuild/reinstall the LibreOffice packages
  from a known-good package contract, not to mutate the running workstation.

Known follow-up:

- Clean stale Flatpak LibreOffice bwrap processes before filming if they are visually confusing.
- Rebuild/reinstall native LibreOffice packages so the VM hotfix becomes package-owned state.
- Consider separate per-module LibreOffice cache/profile directories or locking to avoid symlink/cache collisions when launching multiple modules simultaneously.
