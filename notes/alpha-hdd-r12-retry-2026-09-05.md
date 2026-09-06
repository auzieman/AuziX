# AX-012/task65 — HDD retry after passwd leaf-link fail

September 5, 2026 20:24 PDT, before commit and lab run. Operator: Chrome
is on another desktop; give the HDD another go.

unlock-r11 pre-hdd image stays the source. The pipeline derives the
container run from `hdd_id=alpha-apk-*`, so this retry keeps
`hdd_id=alpha-apk-20260905-alpha-unlock-r11` after parking the failed
`a4e49aa4` work dirs. A new suffix would look for a missing pre-hdd
receipt.

- Pipeline: `auzix-release-hdd-build-deploy`
- HDD ID: `alpha-apk-20260905-alpha-unlock-r11` (same image, parked fail)
- Image: `auzix/validation:pre-hdd-apk-20260905-alpha-unlock-r11`
  `sha256:372909481e60db52cd10015fb867a4859fa79ca1e4a3ac47aca29d4ad3250d8e`
- Target VMID: 146. Not 145. Not 135.
- Method: commit stager, push r730 `cursor-auzix`, park failed dirs
  with a receipt, then `bkc-cli trigger-pipeline` on OpenStack `bkc-alt`

Park (evidence, not delete):

- `/var/lib/auzix-build/hdd-runs/alpha-apk-20260905-alpha-unlock-r11`
  → `.../alpha-apk-20260905-alpha-unlock-r11.failed-a4e49aa4`
- `/var/lib/auzix-build/alpha-hdd/alpha-apk-20260905-alpha-unlock-r11`
  → `.../alpha-apk-20260905-alpha-unlock-r11.failed-a4e49aa4`

Stager change: unlink `/etc/{passwd,group,shadow,gshadow}` then copy
Settings as regular files; assert the same. No user/sshd/E redesign.

Rollback: leave parked fail dirs and the new hdd-run; do not attach
anything to 145. Acceptance: staging passes the regular-file asserts
and existing `sshd -t`; VM 146 start is follow-on. Desktop still
untested.

Kanboard task65 comment sync pending until posted.
