# AUZiX lab park + morning handoff — 2026-08-22

## Park status

- VMID135 and VMID132 were stopped on PVE `192.168.1.9`.
- R730 AUZiX test/build containers were stopped:
  - `auzix-strict-rebase-shell`
  - `auzix-finalize-repo-52d2243d`
- No stray `qemu-system-x86_64` process was found on `lab-ai-worker`.
- `ops/lab-power.sh park` was used from `BlackKnightController`.
- `server1` and `server2` accepted IPMI soft-off and later reported off/down.
- `r730-ai-01` BMC/IPMI still refused RMCP+ sessions, but the OS accepted `systemctl poweroff`; `10.20.0.130:11434` was down afterward.
- Edge services were intentionally left alone; `grafana-edge` and `portainer-edge` still answered in the final smoke.

## Morning resume guardrails

1. Start from BKC/lab notes and pipeline trails; do not invent a new ISO/build path.
2. Keep laptop as control/jump/git only. Heavy work belongs on lab-build/R730.
3. Use `ops/lab-power.sh start`, `wait`, and `status` for lab bring-up from `BlackKnightController`.
4. Treat `auzix-small-moon-pkgtool-only-r3.iso` / `auzix-small-moon-live-smoke-2026-08-22.md` as the known-good boot anchor.
5. Before another ISO attempt, compare the known-good root/init path against the failed r13 path. The r13 artifact was:
   `/var/lib/auzix-build/published/auzix-relaxed-compat-live-r13-no-normalize.iso`
6. Keep package-manager fixes centered on:
   - single core glibc/System library tree;
   - no reinstall/relink of already-present core runtime;
   - resolve full unique dependency plan before install/pull;
   - preserve receipts/package state across install roots.

## Immediate next work

- Bring lab up with `BlackKnightController/ops/lab-power.sh start && ./ops/lab-power.sh wait`.
- Check R730 IPMI credentials/session separately; OS shutdown worked, BMC status did not.
- Re-run AUZiX package-manager proof in a container before touching live ISO/VM targets.
- Only after package-manager proof: build a small live ISO from the known-good ISO builder path, not from a cloned test container root.
