# AX-012/task65 — publish Sudo current from host generation

September 5, 2026 20:42 PDT, before commit. Operator: cannot sit on
r730; continue the next HDD bits. unlock-r11 staging and passwd
materialize already passed. Next fail is Sudo registration.

Sudo is present at `/Programs/Sudo/host/Commands/sudo` and already
published on Compatibility. VM145 is the same. Terminology already has
`current -> /Programs/Terminology/host`. The alpha-final validator and
the auzix sudo probe use `/Programs/Sudo/current/Commands/sudo`.

Change: in `scripts/stage-auzix-alpha-hdd-root.sh`, if `Programs/Sudo/host`
exists and `current` is absent, `ln -sfn /Programs/Sudo/host` to
`Programs/Sudo/current`. Assert the link and that `Commands/sudo` is
executable. Do not rebuild Sudo. Do not invent a second binary.

Proof stays on r730 (KVM available). Park the failed `a5eae325` work
dirs, then reuse `hdd_id=alpha-apk-20260905-alpha-unlock-r11` to VM 146.
Not 145. Not 135.

Rollback: revert the current-link block. Keep parked fail dirs.
Acceptance: validator gets past Sudo/current; existing sshd/passwd
asserts still pass. Guest desktop remains later.

Kanboard task65 comment sync pending.
