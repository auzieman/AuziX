# AuziX Installation Profiles

## Purpose

AuziX is one operating system with two first-class compositions:

1. **Container profile** for headless services, workers, automation, orchestration, and future AuziX-native container images.
2. **Graphical workstation profile** for interactive desktop use, development, visualization, local administration, and hardware-integrated workflows.

These profiles must share a common root contract and package model. They are not separate products and must not drift into independent dependency graphs.

## Architectural invariant

Every component must declare which layer owns it:

- `core`: required by every AuziX composition
- `container`: required only for the headless container runtime profile
- `workstation`: required only for the graphical profile
- `build`: required to construct artifacts but absent from runtime images
- `optional`: role or application bundle installed above a profile

No workstation dependency may become an implicit requirement of `core` or `container`.

## Shared AuziX core

The shared core should contain only the contracts needed to boot or enter the runtime, resolve paths, describe packages, execute deterministic orchestration, and expose health or identity.

Expected ownership:

- Root contract and compatibility bridges
- BusyBox/bootstrap command surface
- Codex Lua + JSON runtime and schema validation
- Package receipts and repository metadata
- Identity, configuration, and state-path resolution
- Minimal user/group and permissions model
- Health, version, and provenance metadata
- Optional service discovery client interfaces, without forcing a desktop or full daemon set

## Container profile

The container profile is the first refactoring target because it provides the smallest executable proof of the AuziX root contract.

It must:

- Build reproducibly from an explicit manifest
- Contain no Xorg, LightDM, Enlightenment, PulseAudio, browser, or workstation-only packages
- Start without systemd assumptions
- Provide a deterministic entrypoint and command path
- Publish architecture, version, source commit, package receipts, and build timestamp policy
- Pass smoke tests without privileged mode
- Support read-only root operation where practical
- Define writable locations explicitly, especially `/Work`, `/Users`, `/Volumes`, and service state
- Remain usable as the future base image for AuziX services

The current `docker import` flow is a useful bootstrap, but it should evolve toward a profile manifest plus a verifiable OCI artifact pipeline. The root filesystem should be assembled intentionally rather than inheriting the complete workstation staging tree and pruning it afterward.

## Graphical workstation profile

The workstation profile composes `core` plus desktop and hardware capabilities:

- Xorg or later display stack
- Enlightenment and session integration
- LightDM or another greeter
- Terminology, XTerm, browsers, and desktop applications
- udev, DBus, ACPI, audio, input, and device integration
- Installer and live-media behavior
- Local developer and administration bundles

The workstation profile may consume container-profile artifacts, but the container profile must never depend on workstation composition.

## Build graph

The desired dependency direction is:

```text
source + manifests
        |
        v
    build tools
        |
        v
     AuziX core
      /      \
     v        v
container   workstation
 profile      profile
    |           |
    v           v
 OCI image   live ISO / disk image / installer media
```

## Container-first milestones

### Milestone 0: Inventory and classification

- Inventory build scripts, packages, staged files, compatibility links, and generated artifacts.
- Assign each item to `core`, `container`, `workstation`, `build`, or `optional`.
- Record unresolved ownership rather than silently choosing a layer.

### Milestone 1: Profile manifests

- Add machine-readable manifests for the shared core and container profile.
- Make the container root derive from those manifests.
- Stop using the entire workstation root as the implicit source of truth.

### Milestone 2: Reproducible container artifact

- Build an OCI image from the profile root.
- Add labels and package receipts.
- Add smoke tests for shell startup, path resolution, package database readability, writable paths, and absence of desktop dependencies.

### Milestone 3: Service-ready base

- Define entrypoint conventions for services and workers.
- Add non-root execution guidance and explicit volumes.
- Prove at least one AuziX-native service image derived from the base.

### Milestone 4: Feed installer and media work

Once profile composition is explicit, reuse it to drive:

- Live ISO package selection
- Installed workstation package selection
- Recovery image composition
- Future unattended install profiles
- Container and workstation update channels

This is the adjacent payoff: container correctness forces package ownership, path resolution, provenance, and artifact composition to become explicit. Those same contracts reduce ambiguity in the installer and live-media pipeline.

## Guardrails for the refactor

- Do not rename foundational paths merely to make the tree look conventional.
- Preserve the AuziX root contract as the product identity.
- Do not replace deterministic manifests with hidden Dockerfile side effects.
- Do not introduce a large init system into the container profile without an explicit service requirement.
- Do not delete legacy scripts until their outputs and side effects are mapped.
- Prefer small commits that leave a buildable or inspectable checkpoint.
- Treat installation media as a consumer of the profile model, not as an unrelated second build system.

## Immediate next engineering slice

1. Generate a repository inventory and package ownership table.
2. Define `profiles/core.json` and `profiles/container.json` schemas.
3. Add a container-root assembly command that consumes those manifests.
4. Add a smoke-test command and wire it into the Makefile and containerized builder.
5. Compare the resulting root with the current `docker import` image before replacing the legacy path.
