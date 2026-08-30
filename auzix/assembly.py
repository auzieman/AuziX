from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

from .apk import bootstrap_root, install_lock_chroot
from .contracts import ContractError
from .package_graph import compose_profile
from .package_graph import load_packages
from .fpm import emit_apk


def _resolve_repository(lock: dict[str, Any], repository: Path) -> list[Path]:
    resolved = []
    for item in lock["packages"]:
        matches = sorted(repository.glob(f"{item['apk_name']}_{item['apk_version']}_*.apk"))
        if len(matches) != 1:
            raise ContractError(
                f"repository preflight expected one APK for {item['name']} "
                f"({item['apk_name']}_{item['apk_version']}_*.apk), found {len(matches)} in {repository}"
            )
        resolved.append(matches[0])
    return resolved


def emit_profile_repository(
    profile_name: str, staging_root: Path, repository: Path, carry_forward: Path | None = None
) -> list[str]:
    """Replace a repository with APKs emitted from the exact profile lock."""
    packages = load_packages()
    lock = compose_profile(profile_name)
    if repository.exists():
        shutil.rmtree(repository)
    repository.mkdir(parents=True)
    emitted = []
    for item in lock["packages"]:
        name = item["name"]
        carried = [] if carry_forward is None else sorted(
            carry_forward.glob(f"{item['apk_name']}_{item['apk_version']}_*.apk")
        )
        if len(carried) > 1:
            raise ContractError(f"multiple carry-forward APKs found for {name}: {carry_forward}")
        if carried:
            shutil.copy2(carried[0], repository / carried[0].name)
        else:
            emit_apk(packages[name][1], staging_root / name, repository)
        emitted.append(name)
    _resolve_repository(lock, repository)
    return emitted


def _installed(root: Path) -> list[str]:
    database = root / "System/State/apk/db/installed"
    if not database.is_file():
        raise ContractError(f"APK installed database is missing: {database}")
    names = []
    for line in database.read_text(encoding="utf-8").splitlines():
        if line.startswith("P:"):
            names.append(line[2:])
    return sorted(names)


def assemble_root(
    profile_name: str,
    target_root: Path,
    bootstrap_packages: Path,
    repository: Path,
    *,
    apk_command: str,
    allow_untrusted: bool,
) -> dict[str, Any]:
    """Build a root with exactly two APK transactions and no filesystem overlay."""
    target_root = target_root.resolve()
    bootstrap_packages = bootstrap_packages.resolve()
    repository = repository.resolve()
    bootstrap_lock = compose_profile("bootstrap-base")
    profile_lock = compose_profile(profile_name)
    # The full lock is proven before touching the output root.  This prevents a
    # successful bootstrap from disguising a stale or incomplete repository.
    _resolve_repository(bootstrap_lock, bootstrap_packages)
    _resolve_repository(profile_lock, repository)
    if target_root.exists():
        shutil.rmtree(target_root)
    bootstrap_argv = bootstrap_root(
        bootstrap_lock,
        target_root,
        bootstrap_packages,
        apk_command=apk_command,
        allow_untrusted=allow_untrusted,
    )
    install_argv = install_lock_chroot(
        profile_lock, target_root, repository, allow_untrusted=allow_untrusted
    )
    expected = sorted(
        {item["apk_name"] for item in bootstrap_lock["packages"]}
        | {item["apk_name"] for item in profile_lock["packages"]}
    )
    actual = _installed(target_root)
    if actual != expected:
        raise ContractError(
            "assembled APK state differs from locks: "
            + json.dumps({"expected": expected, "actual": actual}, sort_keys=True)
        )
    return {
        "format": "auzix-apk-assembly-proof-v1",
        "status": "passed",
        "profile": profile_name,
        "root": str(target_root),
        "packages": actual,
        "bootstrap_argv": bootstrap_argv,
        "install_argv": install_argv,
        "filesystem_overlay": False,
    }


def emit_and_assemble_root(
    profile_name: str,
    staging_root: Path,
    target_root: Path,
    bootstrap_packages: Path,
    repository: Path,
    *,
    apk_command: str,
    allow_untrusted: bool,
) -> dict[str, Any]:
    emitted = emit_profile_repository(
        profile_name, staging_root.resolve(), repository.resolve(), bootstrap_packages.resolve()
    )
    result = assemble_root(
        profile_name,
        target_root,
        bootstrap_packages,
        repository,
        apk_command=apk_command,
        allow_untrusted=allow_untrusted,
    )
    result["emitted"] = emitted
    result["staging_root"] = str(staging_root.resolve())
    result["repository"] = str(repository.resolve())
    return result
