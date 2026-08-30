from __future__ import annotations

import shutil
from pathlib import Path
from typing import Any

from .contracts import ContractError
from .contracts import read_json
from .process import run
from .names import apk_name, apk_version


def validate_staged_payload(package: dict[str, Any], staged_root: Path) -> None:
    for absolute, expected in package["validation"].get("required_shebangs", {}).items():
        path = staged_root / absolute.lstrip("/")
        if not path.is_file():
            raise ContractError(f"{package['name']}: required script is missing: {absolute}")
        with path.open("rb") as handle:
            actual = handle.readline().decode("utf-8", errors="replace").rstrip("\r\n")
        if actual != expected:
            raise ContractError(
                f"{package['name']}: stale shebang in {absolute}: {actual!r}; expected {expected!r}"
            )


LIFECYCLE_FLAGS = {
    "before_install": "--before-install",
    "after_install": "--after-install",
    "before_remove": "--before-remove",
    "after_remove": "--after-remove",
}


def package_lifecycle_scripts(
    package: dict[str, Any], staged_root: Path, receipt: dict[str, Any] | None = None
) -> list[tuple[str, Path]]:
    declared = package.get("lifecycle")
    retained = [] if receipt is None else [
        path for path in receipt.get("maintainer_surfaces", [])
        if Path(path).name in {"preinst", "postinst", "prerm", "postrm"}
    ]
    if declared is None:
        if retained:
            raise ContractError(
                f"{package['name']}: receipt retains maintainer scripts but package JSON has no lifecycle annotation"
            )
        return []
    result = []
    declared_paths = []
    for stage, flag in LIFECYCLE_FLAGS.items():
        absolute = declared[stage]
        if absolute is None:
            continue
        absolute = absolute.replace("${version}", package["version"])
        script = staged_root / absolute.lstrip("/")
        if not script.is_file():
            raise ContractError(f"{package['name']}: declared lifecycle script is missing: {absolute}")
        if not script.read_bytes().startswith(b"#!"):
            raise ContractError(f"{package['name']}: lifecycle script has no shebang: {absolute}")
        declared_paths.append(absolute)
        result.append((flag, script))
    if retained and set(retained) != set(declared_paths):
        raise ContractError(
            f"{package['name']}: lifecycle annotation does not match retained maintainer scripts: "
            f"declared={sorted(declared_paths)!r} retained={sorted(retained)!r}"
        )
    return result


def receipt_fpm_metadata(package: dict[str, Any], staged_root: Path) -> tuple[list[str], list[tuple[str, Path]]]:
    dependencies = list(package["dependencies"]["runtime"])
    receipt_glob = package["source"].get("receipt_glob")
    if not receipt_glob:
        return dependencies, []
    receipts = sorted(staged_root.glob(receipt_glob))
    if len(receipts) != 1:
        raise ContractError(
            f"{package['name']}: expected one source receipt matching {receipt_glob}, found {len(receipts)}"
        )
    receipt = read_json(receipts[0])
    return dependencies, package_lifecycle_scripts(package, staged_root, receipt)


def emit_apk(package: dict[str, Any], staged_root: Path, output_dir: Path, *, dry_run: bool = False) -> list[str]:
    if not staged_root.is_dir():
        raise ContractError(f"staged package root does not exist: {staged_root}")
    if not shutil.which("fpm"):
        raise ContractError("fpm is required to emit APK packages")
    validate_staged_payload(package, staged_root)
    dependencies, lifecycle = receipt_fpm_metadata(package, staged_root)
    output_dir.mkdir(parents=True, exist_ok=True)
    argv = [
        "fpm", "-s", "dir", "-t", "apk",
        "--name", apk_name(package["name"]),
        "--version", apk_version(package["version"]),
        "--package", str(output_dir),
        "--chdir", str(staged_root),
    ]
    for dependency in dependencies:
        argv.extend(["--depends", apk_name(dependency)])
    for flag, script in lifecycle:
        argv.extend([flag, str(script)])
    argv.append(".")
    if not dry_run:
        run(argv)
    return argv
