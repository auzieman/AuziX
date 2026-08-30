from __future__ import annotations

import shutil
import hashlib
import json
from pathlib import Path
from typing import Any

from .contracts import ContractError
from .process import run
from .layout import activate_layout


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def compose_apk_layers(layers: list[Path], output_dir: Path) -> dict[str, Any]:
    """Flatten APK directories in priority order; the last layer wins by filename."""
    if not layers:
        raise ContractError("APK layer composition received no layers")
    selected: dict[str, tuple[int, Path]] = {}
    for priority, layer in enumerate(layers):
        if not layer.is_dir():
            raise ContractError(f"APK layer does not exist: {layer}")
        packages = sorted(layer.glob("*.apk"))
        if not packages:
            raise ContractError(f"APK layer contains no packages: {layer}")
        for package in packages:
            selected[package.name] = (priority, package)
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)
    records = []
    for filename, (priority, source) in sorted(selected.items()):
        destination = output_dir / filename
        shutil.copy2(source, destination)
        digest = _file_sha256(destination)
        records.append({
            "filename": filename,
            "layer": str(layers[priority]),
            "sha256": digest,
        })
    result = {
        "format": "auzix-apk-layer-lock-v1",
        "layers": [str(layer) for layer in layers],
        "count": len(records),
        "packages": records,
    }
    (output_dir / "layer-lock.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return result


def _resolve_lock_packages(lock: dict[str, Any], package_dir: Path) -> list[Path]:
    package_dir = package_dir.resolve()
    resolved_packages = []
    for item in lock["packages"]:
        matches = sorted(package_dir.glob(f"{item['apk_name']}_{item['apk_version']}_*.apk"))
        if len(matches) != 1:
            raise ContractError(f"expected one APK for {item['name']}, found {len(matches)} in {package_dir}")
        resolved_packages.append(matches[0])
    return resolved_packages


def install_lock(lock: dict[str, Any], target_root: Path, repositories_file: Path, *, apk_command: str = "apk", package_dir: Path | None = None, keys_dir: Path | None = None, allow_untrusted: bool = False, dry_run: bool = False) -> list[str]:
    resolved_apk = shutil.which(apk_command) if "/" not in apk_command else apk_command
    if not resolved_apk or not Path(resolved_apk).is_file():
        raise ContractError(f"apk-tools command is not available: {apk_command}")
    if not repositories_file.is_file():
        raise ContractError(f"APK repositories file does not exist: {repositories_file}")
    external = [item["name"] for item in lock["packages"] if item["kind"] == "external-provider"]
    if external:
        raise ContractError("lock contains external providers: " + ", ".join(external))
    target_root.mkdir(parents=True, exist_ok=True)
    argv = [resolved_apk, "add", "--initdb", "--root", str(target_root), "--repositories-file", str(repositories_file)]
    if allow_untrusted:
        argv.append("--allow-untrusted")
    if keys_dir:
        argv.extend(["--keys-dir", str(keys_dir)])
    if package_dir:
        argv.extend(map(str, _resolve_lock_packages(lock, package_dir)))
    else:
        argv.extend(f"{item['apk_name']}={item['apk_version']}" for item in lock["packages"])
    if not dry_run:
        run(argv)
    return argv


def bootstrap_root(
    lock: dict[str, Any], target_root: Path, package_dir: Path, *, apk_command: str, allow_untrusted: bool
) -> list[str]:
    names = [item["name"] for item in lock["packages"]]
    if names != ["BaseLayout", "BusyBox", "ApkTools"]:
        raise ContractError(
            "bootstrap lock must contain BaseLayout, BusyBox and ApkTools, found: "
            + ", ".join(names)
        )
    target_root = target_root.resolve()
    target_root.mkdir(parents=True, exist_ok=True)
    repositories = target_root.parent / f".{target_root.name}.bootstrap.repositories"
    repositories.write_text("\n", encoding="utf-8")
    try:
        argv = install_lock(
            lock,
            target_root,
            repositories,
            apk_command=apk_command,
            package_dir=package_dir,
            allow_untrusted=allow_untrusted,
        )
    finally:
        repositories.unlink(missing_ok=True)
    activate_layout(target_root)
    return argv


def install_lock_chroot(
    lock: dict[str, Any], target_root: Path, package_dir: Path, *, allow_untrusted: bool
) -> list[str]:
    target_root = target_root.resolve()
    apk = target_root / "Programs/ApkTools/current/Commands/apk"
    if not apk.is_file():
        raise ContractError(f"root does not contain packaged APK tools: {apk}")
    packages = _resolve_lock_packages(lock, package_dir)
    return install_apks_chroot(packages, target_root, allow_untrusted=allow_untrusted)


def install_apks_chroot(packages: list[Path], target_root: Path, *, allow_untrusted: bool) -> list[str]:
    if not packages:
        raise ContractError("chroot APK transaction received no packages")
    target_root = target_root.resolve()
    apk = target_root / "Programs/ApkTools/current/Commands/apk"
    if not apk.is_file():
        raise ContractError(f"root does not contain packaged APK tools: {apk}")
    intake = target_root / "Work/PackageIntake"
    if intake.exists():
        shutil.rmtree(intake)
    intake.mkdir(parents=True)
    inside_packages = []
    for package in packages:
        destination = intake / package.name
        shutil.copy2(package, destination)
        inside_packages.append("/Work/PackageIntake/" + package.name)
    argv = ["chroot", str(target_root), "/Programs/ApkTools/current/Commands/apk", "add"]
    if allow_untrusted:
        argv.append("--allow-untrusted")
    argv.extend(inside_packages)
    try:
        run(argv)
    finally:
        shutil.rmtree(intake)
    return argv
