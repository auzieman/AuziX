# AUZiX package factory v2

This tree is the authoritative design surface for the APK-backed package
factory. Existing builders remain available as compatibility producers while
their payload knowledge is extracted into small JSON fragments.

Authority flows in one direction:

1. package JSON describes intent and existing payload provenance;
2. profile JSON selects package names;
3. `python3 -m auzix` validates and composes an immutable lock;
4. a package adapter will stage the payload and ask FPM to emit a signed APK;
5. apk-tools owns dependency resolution, installation and installed state;
6. activation derives compatibility, service and desktop surfaces;
7. media writers only wrap a validated root.

HDD, ISO and OCI writers may not change package-owned files.

Run the initial proof locally:

```sh
python3 -m auzix validate
python3 -m auzix compose-profile pilot-core --output /tmp/pilot-core.lock.json
python3 -m auzix compose-target base-netinstall-hdd --output /tmp/base-netinstall-hdd.plan.json
python3 -m auzix preflight base-netinstall-hdd
```

The first build target is `base-netinstall-hdd`. It ports the proven tiny
netinstall seed and SSH-first acceptance contract. Desktop packages remain a
later profile layered onto a passing package-built base root.

The pilot deliberately pairs FPM 1.17.0 with the pinned APK 2.14.10 static
transaction engine. APK v3 is outside this pilot because its stricter APK v2
validation is not compatible with FPM 1.17.0 output.
