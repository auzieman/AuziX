# APK alpha BKC run — September 4

The current alpha build is now invoked through the existing BKC
`auzix-release-container-validate` workflow on the OpenStack runtime.
The wrapper lives in BlackKnightController's
`pipelines/auzix-release-container-validate/scripts/build-three-release-containers.sh`.
Internal source branches are `alpha-apk-release-20260904` (AuziX) and
`alpha-apk-pipeline-20260904` (BKC). Nothing has been publicly promoted.

- Input preflight: `87633e17-ce1e-417d-b3e0-4f14bf8389e5`, passed.
  Its inherited stage completion wording overstated image validation; the
  actual log explicitly says `mode=preflight`. BKC commit `c6807b7` corrects
  that wording for subsequent runs.
- Full package/container attempt: `03167bb4-8d50-4011-a2c7-9d2b115e03be`,
  source `dda4d2736ff62dc1f0dd71e3050eb671910a2215`.
  Work: `/var/lib/auzix-build/pre-hdd-apk/20260904-alpha-bkc-r1`.
  Log: `/var/lib/auzix-build/receipts/apk-alpha-20260904-alpha-bkc-r1.log`.
  Completed all 62 archive conversions, native support emission, retained
  container/disk package emission and EFL frontend emission. Stopped in
  Nginx APK dependency resolution, before pre-HDD or HDD success.
- Exact failure: local repository argument `/Repository/x86_64` caused APK
  to miss its index. `262d51a` changes it to `/Repository`. The targeted BKC
  mode `release_id=apk-alpha-nginx` reuses this run's emitted packages and
  zero image, builds only Nginx from a new pinned commit, and checks Nginx
  configuration and Curl. It does not replace the live repository container.
- `95fed80` adds explicit native-to-archive APK dependency mappings for the
  actual `enlightenment` and `flatpak` providers. 59 factory tests and package
  manifest validation pass. This change is not in the full attempt above;
  it must be included in subsequent package emission.
- `dda4d27` removes boot mounts from the ServiceRuntime APK install hook and
  retains the known devpts/ptmx fix in the existing boot service producer.

Remaining closure/installer/runtime acceptance is tracked in
`alpha-release-readiness-2026-09-04.md`. Do not infer a working root from
package emission. No unattended full retry until the failing boundary and
remaining selected dependency closure have a focused proof.

After image and installation acceptance, reuse the existing Auzietek public
article/site and `auzix-public-beta-shelf` pipelines for auzietek.com,
auzix.auzietek.com and the public APK repository. Update the existing shelf's
APK/HDD artifact handling; retain the existing public host/TLS ownership.
