# AX-012/task65 — HDD phase 2 after unlock-r11

September 5, 2026 18:26 PDT, before HDD. Operator: into the second
phase now. apk-alpha `20260905-alpha-unlock-r11` already converted the
117 (97 passed + 20 static) and is still emitting installer/repo/images.
HDD starts when `pre-hdd.receipt` is pass.

- Pipeline: `auzix-release-hdd-build-deploy`
- HDD ID: `alpha-apk-20260905-alpha-unlock-r11`
- Source: `a9dcd2859514d6146cf619ad9b6bfe3a65e63413`
- Target VMID: 146 (free). Not 145. Not 135.
- Method: `bkc-cli trigger-pipeline` on OpenStack `bkc-alt`

Rollback: leave the new hdd-run directory; do not attach the disk to
145. Acceptance: image receipt exists; VM 146 start is optional follow-on.
Install/desktop still untested until the guest is up.

18:31 PDT operator: another phase. PVE 146 free. 145 running.

18:34 PDT unlock-r11 passed. Image
`auzix/validation:pre-hdd-apk-20260905-alpha-unlock-r11`
`sha256:372909481e60db52cd10015fb867a4859fa79ca1e4a3ac47aca29d4ad3250d8e`.
Pipeline receipt mode=run status=pass.

Started: BKC `a4e49aa4` queued HDD. Work
`/var/lib/auzix-build/hdd-runs/alpha-apk-20260905-alpha-unlock-r11`.
Failed `rc=1` at host `cp` through exported `/etc/passwd` symlink.
See `notes/alpha-hdd-phase2-fail-passwd-2026-09-05.md`. VM145 untouched.
VM146 not created.
