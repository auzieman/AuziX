# Auzix Package Walkthrough

The first package client uses repository JSON as its transport metadata and a
local JSON transaction cache. This keeps the schema inspectable while package
semantics are still changing. SQLite can replace the local cache later without
changing package archives or repository indexes.

## Repository

The current lab repository is:

```text
http://192.168.1.10/auzix/repo
```

Refresh its metadata:

```sh
auzix-pkg refresh
```

An alternate repository can be selected explicitly:

```sh
auzix-pkg refresh http://server/path/to/repo
```

## Inspect Packages

```sh
auzix-pkg list all
auzix-pkg list installed
auzix-pkg list available
auzix-pkg info Midori
```

The cached repository index and installed transaction state are stored at:

```text
/System/State/packages/repo-index.json
/System/State/packages/installed.json
```

## Install

```sh
auzix-pkg install XTerm
auzix-pkg install Midori
auzix-pkg install AuzixThemes
auzix-pkg install AuzixWallpapers
```

The client resolves published dependencies, downloads each archive, verifies
its SHA-256 checksum, rejects unsafe archive paths, extracts it, and atomically
updates local installed state. Package-owned post-install hooks may export
assets into global catalogs; hooks are restricted to executable paths under
`/Programs`.

Installing an unchanged package is a no-op. A package with the same version but
a different repository checksum is reinstalled, allowing early AuziX package
iterations without artificial version changes.

## Base Image Bootstrap

Image construction can seed transaction state while leaving packages available
for installer tests:

```sh
auzix-pkg refresh
auzix-pkg bootstrap Midori XTerm
```

This records every repository package except the named exclusions as belonging
to the base image.

Package removal is not implemented yet. It requires complete file manifests and
shared-path ownership checks before it can safely delete compatibility exports.
