September 5, 2026 16:09 PDT — AX-012/task65.

VM145 is close enough and stays the reference. No new HDD until intake
validation has a receipt. prove-factory was failing because the effects
script always exited 1 and `completed-with-review` was treated as a crash.
Those are mapper leftovers, not an AuziX OS bug.

Starting BKC `auzix-release-container-validate` as `apk-alpha-prove-factory`,
run `20260905-intake-validate`, through `bkc-cli`. HDD still locked.
