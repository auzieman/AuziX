# AX-012/task65 — Debian D-Bus install observation started

September 5, 2026 15:46 PDT. Executes the already-recorded action
`alpha-debian-install-trace-action-2026-09-05.md`. No mapping repair in this
step. The 35 held packages remain needs-review until this baseline exists.

Operator correction: Debian installs these packages. AuziX intake/APK mapping
is the failing surface. Previous AX-012 source-audit proofs compared source
and ran a helper fixture; they did not run `apt-get install dbus=1.16.2-2`.

- Source: `fea2a20a36333dbd7bd80dcc19d45f42dbe4aac1` (already on r730 bare repo)
- Worker: `apk-alpha-source-audit` via
  `pipelines/auzix-release-container-validate/scripts/build-three-release-containers.sh`
- Run ID: `20260905-debian-install-trace`
- Output: `/var/lib/auzix-build/package-proof/AX-012-source-fea2a20a3633`
- Log: `/var/lib/auzix-build/receipts/apk-alpha-20260905-debian-install-trace-resume-fea2a20a3633.log`
- Protected: VM145, R8/R10, existing AX-012 proofs, healthy r730 containers

BKC OpenStack FIP `10.20.0.232:5000` returns 302 from ns1; manager
`10.20.0.230:5000` timed out. This invocation uses the committed worker script
on R730 rather than a Flask/UI queue token. Record a BKC run UUID later if
the UI path is restored; do not re-run the observation.

Monitor:

```sh
ssh r730-ai-01 'tail -F /var/lib/auzix-build/receipts/apk-alpha-20260905-debian-install-trace-resume-fea2a20a3633.log'
```
