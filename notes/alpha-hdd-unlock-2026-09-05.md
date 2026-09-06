# AX-012/task65 — unlock HDD after leftover capture

September 5, 2026 18:10 PDT, before lab run. Operator: capture leftover
logic to files that can be worked with if not already worked around,
then unlock and build the container/HDD stack. VM145 stays the
reference and is not mutated.

Intake receipts already exist: held r8 `AX-012-5f73ec794f55` and HDD
117 `AX-012-5f73ec794f55-hdd`. The ten HDD packages with parked
leftovers are copied to `packaging/legacy-leftovers/` with
`index.json` (already vs still-missing). First-boot
`/System/Boot/PostInstall` inventories those files and ensures
`/Services/{acpid,glances,fstrim}/run` when the program is present.
It does not execute leftover Debian scripts.

Unlock: assemble a new pre-HDD and HDD. Not VM145. Target VM 146
(free). Preserve 135/145.

- Pipeline 1: `auzix-release-container-validate` `apk-alpha`
  run `20260905-alpha-unlock-r11`
- Then HDD: `auzix-release-hdd-build-deploy`
  `hdd_id=alpha-apk-20260905-alpha-unlock-r11` `target_vmid=146`
- Method: `bkc-cli trigger-pipeline` on OpenStack `bkc-alt`
- Protected: VM145 running, VM135 stopped original disk

Rollback: leave new work dirs; do not reuse run IDs; do not attach
the new disk to 145. Install acceptance remains a later guest check.
