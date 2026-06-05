# Licensing Direction

## Goal

The desired model is:

- attribution required
- source is visible and useful for learning, testing, and personal builds
- non-commercial use is free
- commercial use should sponsor or commercially license the project
- no per-seat friction for ordinary users

That is a source-available model, not an OSI open-source model. OSI-style open
source permits commercial use, so a non-commercial restriction needs a different
license family.

## Best Fit

Recommended first fit:

```text
PolyForm Noncommercial 1.0.0
+ separate Commercial/Sponsor License
```

Why:

- it is designed for software
- it clearly allows non-commercial use
- it leaves room for separate commercial terms
- it is easier to understand than a custom license

Commercial terms can be simple:

```text
Commercial production use requires an active sponsorship or a written commercial
license from the project owner.
```

This keeps personal, educational, lab, hobby, and evaluation use free while
asking companies using AuziX commercially to support the work.

## Alternatives

### AGPL-3.0-or-later

Use this only if AuziX should be true open source. It allows commercial use, but
requires source sharing for distributed/network-modified versions. It cannot
require sponsorship for commercial use.

### Business Source License 1.1

Use this if we want time-delayed open source. It can restrict production use at
first, then convert to GPL/Apache/MIT after a defined change date. This is more
formal and heavier than the current AuziX need.

### Creative Commons NonCommercial

Avoid for code. Creative Commons licenses are useful for art, docs, and media,
but they are not the right default for software.

## Practical Repo Layout

Once the final choice is made:

```text
LICENSE                         public source-available license
COMMERCIAL-LICENSE.md           commercial/sponsor terms summary
NOTICE                          attribution and project identity
```

If docs/artwork/themes later need different handling, add:

```text
docs/LICENSE-DOCS
assets/LICENSE-ASSETS
```

## Current Recommendation

Use:

```text
Code: PolyForm Noncommercial 1.0.0
Commercial use: sponsor or written commercial license
Docs: CC BY-NC 4.0 or same as code
Generated distro artifacts: same terms unless a package inside them requires
different redistribution terms
```

Before publishing binaries, audit bundled package licenses. AuziX can license
its own build scripts and glue, but it cannot relicense Debian, Enlightenment,
BusyBox, Xorg, NetSurf, or other upstream components.
