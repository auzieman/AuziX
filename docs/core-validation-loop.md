# AuZiX Core Validation Loop

The VM and ISO paths prove real boot behavior, but they are too expensive for
normal root OS debugging. Core issues such as users, permissions, `/proc`,
library paths, browser profile state, and package receipts should fail before a
Proxmox run starts.

## Operating Order

Use this order for sustaining work:

1. Build the strict root.
2. Run root and package runtime audits.
3. Import the strict root as a container and run a small CLI smoke test.
4. Run the proof-runtime gate, including strict alias policy, terminfo,
   Python-script wrappers, root/user identity, core library floor, and
   wrapper-aware dependency ladder checks.
5. Generate an Ollama-ready triage prompt from the bounded evidence.
6. Only then build ISO media or recreate a VM.

The local entry point is:

```sh
make auzix-core-validation
```

Outputs land under:

```text
out/core-validation/summary.json
out/core-validation/ollama-prompt.md
out/core-validation/strict-root-audit.txt
out/core-validation/package-runtime-audit.txt
out/core-validation/container-smoke.txt
out/auzix-strict/proof-runtime-validation.txt
```

## Scope Boundary

This loop intentionally avoids inventing another init framework. The current
goal is to make existing root invariants observable and repeatable.

Near-term cleanup should bias toward:

- package-owned users, permissions, compatibility exports, and validation
- short CLI checks for each graphical package before full desktop launch
- structured JSON evidence over free-form shell output where practical
- Lua orchestration only after the shell contract is understood and stable

## Outside Guidance

`outside-guidance.md` and `outside-buildroot.md` are design input, not direct
implementation contracts. The useful shared direction is:

- do not duplicate Linux dependency engines in fragile shell parsing
- delegate driver dependency work to `modprobe` or other native tools
- keep boot decisions as structured data before translating them to Lua
- use a target root or container to validate structure before boot media

## Ollama Worker Contract

The slow worker should receive `out/core-validation/ollama-prompt.md`, not the
entire repository. Its response should stay in this shape:

```text
finding:
evidence:
package-owned fix:
boot-script fallback, if still needed:
validation command:
```

That keeps the worker focused on one failed loop instead of re-planning the
whole distribution.
