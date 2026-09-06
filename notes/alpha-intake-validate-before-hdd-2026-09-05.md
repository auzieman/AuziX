# Intake validation before another HDD

September 5, 2026 16:04 PDT. VM145 (`192.168.1.58`) is the close-but-not-perfect
reference. Do not assemble or deploy another HDD until intake validation has a
receipt. Fallout on 145 stays diagnostic.

## Ladder (existing pipelines, cleaned)

1. Local / Trixie unit tests (`python3 -m unittest` in `auzix/trixie-builder:lab`).
2. `apk-alpha-source-audit` — Debian install observation (already passed for D-Bus).
3. `apk-alpha-prove-factory` — convert the held set from
   `AX-012-376e00389e32`, compare findings, **do not** treat
   `completed-with-review` as a crash. Install still untested.
4. Container lane only: zero → nginx → netinstall / pre-HDD image checks.
5. HDD (`auzix-release-hdd-build-deploy`) unlocked 18:10 PDT after
   r8 + HDD 117 receipts. New assemble uses a free VMID (146), never 145.
   See `notes/alpha-hdd-unlock-2026-09-05.md`.

## Pipeline mess to clean, not replace

`build-three-release-containers.sh` stacks many `apk-alpha-*` aliases in one
script. Keep that worker; stop using `jq -e '.status == "passed"'` as the
prove-factory gate. Conversion can finish with remaining mapping families.
That leftover is intake work, not an AuziX OS failure and not an HDD trigger.

`auzix-vm-product-validation` still names VM135. Do not aim it at 145 or a new
disk until step 3/4 pass.

## This step

Fix the prove-factory exit gate and keep unit tests green. No VM, image, or
HDD mutation. Any later lab run that alters the environment goes through
`bkc-cli` with a paper trail. Rollback: revert the prove-factory script and
ledger note.
