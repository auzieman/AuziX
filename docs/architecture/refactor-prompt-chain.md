# AuziX Refactor Prompt Chain

This chain is designed for human-guided work by ChatGPT, Codex, Cursor, Ollama, or another engineering agent. Each stage produces evidence for the next stage. Agents must not skip directly from repository reading to broad refactoring.

## Shared operating context

AuziX is one operating system with two first-class installation profiles:

- A headless container profile for services, workers, automation, orchestration, and future containers built from the AuziX distribution itself.
- A graphical workstation profile for interactive desktop use, local administration, development, visualization, and hardware integration.

Both profiles share an AuziX core, root contract, package model, path resolver, configuration model, and provenance system. The container profile is the first implementation target. Work on it must reinforce, not fork away from, the installer and media architecture.

## Stage 1: Repository archaeology

### Instruction

Analyze the repository without modifying code. Infer the current architecture from build scripts, package definitions, generated roots, installer logic, tests, documentation, and artifact paths.

Produce:

1. A build-entrypoint map.
2. A generated-artifact map.
3. A package and dependency inventory.
4. A list of hardcoded FHS or host paths.
5. A list of places where live-media, installed-system, container, workstation, and build-host concerns are coupled.
6. A table assigning each discovered component to `core`, `container`, `workstation`, `build`, `optional`, or `unresolved`.
7. Risks and unanswered questions.

Do not refactor. Cite paths and relevant functions or targets for every conclusion.

### Acceptance gate

A human must be able to trace each architectural claim back to repository evidence. Unknowns must remain marked as unknowns.

## Stage 2: Current container truth

### Instruction

Trace the existing `auzix-strict-container` build from source inputs to final image. Determine exactly what enters the image, what is inherited accidentally from the workstation root, and what runtime assumptions are present.

Produce:

1. The exact prerequisite target chain.
2. The root filesystem source and pruning behavior.
3. Entrypoint, command, PATH, user, writable-path, and privilege assumptions.
4. Desktop or installer artifacts that leak into the image.
5. Missing OCI metadata and provenance.
6. A smoke-test plan that can run without privileged mode.

Do not replace the current path yet.

### Acceptance gate

The existing image can be described as a deterministic set of inputs and runtime contracts, or the report clearly identifies why it cannot.

## Stage 3: Profile contract

### Instruction

Design machine-readable profile manifests for `core` and `container`. Preserve the AuziX root contract. Do not model the profiles as generic Linux package lists alone.

The design must express:

- Included AuziX packages and versions
- Required directories
- Compatibility bridges
- Runtime user and group expectations
- Writable and read-only paths
- Entrypoint and command contracts
- Health and identity commands
- Artifact labels and provenance
- Optional architecture-specific additions
- Explicit exclusions, especially workstation components

Provide a schema, example manifests, and migration compatibility with the current build.

### Acceptance gate

The container root can be explained solely from source artifacts plus profile manifests. Workstation-only packages are excluded structurally rather than by cleanup guesses.

## Stage 4: Parallel container assembly

### Instruction

Implement a new container-root assembly path beside the current path. Do not delete or silently alter the legacy builder.

Requirements:

1. Consume the approved core and container manifests.
2. Assemble into a clean output directory.
3. Fail on unresolved package references or unexpected host-path leakage.
4. Emit package receipts and provenance.
5. Produce an OCI-compatible image.
6. Add smoke tests for shell startup, PATH resolution, AuziX package database, expected writable paths, read-only-root compatibility where practical, and absence of workstation dependencies.
7. Add comparison tooling between legacy and profile-built roots.

### Acceptance gate

The profile-built container passes smoke tests and its differences from the legacy image are reviewed.

## Stage 5: First AuziX-native service

### Instruction

Choose one small existing service or worker and build it from the AuziX container base. Avoid selecting a desktop-adjacent component.

Demonstrate:

- Non-root execution where practical
- Explicit configuration and state paths
- Health checking
- Signal handling and clean shutdown
- Package provenance
- Local Docker or Podman execution
- A minimal Compose example

### Acceptance gate

The base image proves useful as a parent artifact rather than only as an interactive shell.

## Stage 6: Feed the installer and media model

### Instruction

Use the profile model to identify duplicated or implicit package selection in the live ISO, installed workstation, recovery, and disk-image paths.

Propose how `core` and `workstation` manifests can drive:

- Live-media composition
- Installed-system composition
- Recovery media
- Unattended installation
- Update channels
- Artifact provenance

Do not redesign the installer UI in this stage. Focus on composition contracts and path-context correctness.

### Acceptance gate

Container, ISO, and installed workstation artifacts share one explicit package-composition model while retaining profile-specific behavior.

## Agent behavior rules

- Work one stage at a time.
- Prefer evidence over aesthetic cleanup.
- Never treat shell-script length as proof that a script should be rewritten.
- Do not introduce new frameworks until the existing outputs are mapped.
- Keep the old build path available until parity is demonstrated.
- Separate host-build paths from target-root paths in every analysis and change.
- Mark inferred intent separately from verified behavior.
- Stop and report when repository evidence contradicts the architectural premise.
- Use small commits with narrow, descriptive messages.
- End each stage with changed files, commands run, results, unresolved risks, and the exact recommended next stage.
