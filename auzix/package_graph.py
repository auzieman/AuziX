from __future__ import annotations

from pathlib import Path
from typing import Any

from .contracts import ContractError, content_sha256, read_json
from .paths import PACKAGING_ROOT, REPOSITORY_ROOT
from .names import apk_name, apk_version


def validate_package(path: Path, package: dict[str, Any]) -> None:
    allowed = {
        "format", "name", "version", "source", "layout", "dependencies",
        "lifecycle", "fragments", "payload", "validation", "intake_adapter",
    }
    required = {"format", "name", "version", "source", "layout", "dependencies", "validation"}
    missing = sorted(required - package.keys())
    unknown = sorted(package.keys() - allowed)
    if missing:
        raise ContractError(f"{path}: missing keys: {', '.join(missing)}")
    if unknown:
        raise ContractError(f"{path}: unknown keys: {', '.join(unknown)}")
    if package["format"] != "auzix-package-v1":
        raise ContractError(f"{path}: unsupported format {package['format']!r}")
    runtime = package["dependencies"].get("runtime")
    commands = package["validation"].get("commands")
    required_shebangs = package["validation"].get("required_shebangs", {})
    if not isinstance(runtime, list) or not all(isinstance(item, str) for item in runtime):
        raise ContractError(f"{path}: dependencies.runtime must be a string array")
    providers = package["dependencies"].get("apk_providers", {})
    if not isinstance(providers, dict) or not all(
        name in runtime and isinstance(atom, str) and atom and not any(c.isspace() for c in atom)
        for name, atom in providers.items()
    ):
        raise ContractError(f"{path}: dependencies.apk_providers must map runtime names to APK atoms")
    if not isinstance(commands, list) or not commands or not all(isinstance(item, str) for item in commands):
        raise ContractError(f"{path}: validation.commands must be a non-empty string array")
    if not isinstance(required_shebangs, dict) or not all(
        isinstance(key, str) and key.startswith("/") and isinstance(value, str) and value.startswith("#!")
        for key, value in required_shebangs.items()
    ):
        raise ContractError(f"{path}: validation.required_shebangs must map absolute paths to shebangs")
    lifecycle = package.get("lifecycle")
    if lifecycle is not None:
        stages = {"before_install", "after_install", "before_remove", "after_remove"}
        if not isinstance(lifecycle, dict) or set(lifecycle) != stages:
            raise ContractError(f"{path}: lifecycle must declare exactly {', '.join(sorted(stages))}")
        for stage, script in lifecycle.items():
            if script is not None and (not isinstance(script, str) or not script.startswith("/")):
                raise ContractError(f"{path}: lifecycle.{stage} must be an absolute path or null")
    intake_adapter = package.get("intake_adapter")
    if intake_adapter is not None:
        if not isinstance(intake_adapter, dict) or intake_adapter.get("format") != "auzix-lifecycle-adapter-v1":
            raise ContractError(f"{path}: invalid lifecycle intake adapter")
        template_dir = intake_adapter.get("template_dir")
        if not isinstance(template_dir, str) or not (REPOSITORY_ROOT / template_dir).is_dir():
            raise ContractError(f"{path}: lifecycle adapter template directory is missing")
    surfaces = package.get("payload", {}).get("surfaces", [])
    if not isinstance(surfaces, list) or not all(isinstance(item, str) and item.startswith("/") for item in surfaces):
        raise ContractError(f"{path}: payload.surfaces must be an array of absolute paths")
    legacy_entrypoint = package["source"].get("legacy_entrypoint")
    if legacy_entrypoint and not (REPOSITORY_ROOT / legacy_entrypoint).exists():
        raise ContractError(f"{path}: legacy entry point does not exist: {legacy_entrypoint}")
    producer_argv = package["source"].get("producer_argv")
    if producer_argv is not None and (
        not isinstance(producer_argv, list)
        or not producer_argv
        or not all(isinstance(item, str) and item for item in producer_argv)
    ):
        raise ContractError(f"{path}: source.producer_argv must be a non-empty string array")


def load_packages() -> dict[str, tuple[Path, dict[str, Any]]]:
    packages: dict[str, tuple[Path, dict[str, Any]]] = {}
    for path in sorted((PACKAGING_ROOT / "packages").glob("*/package.json")):
        package = read_json(path)
        validate_package(path, package)
        name = package["name"]
        if name in packages:
            raise ContractError(f"duplicate package name {name}: {path} and {packages[name][0]}")
        packages[name] = (path, package)
    if not packages:
        raise ContractError("no package definitions found")
    return packages


def dependency_order(selected: list[str], packages: dict[str, tuple[Path, dict[str, Any]]]) -> list[str]:
    ordered: list[str] = []
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(name: str) -> None:
        if name in visited:
            return
        if name in visiting:
            raise ContractError(f"dependency cycle at {name}")
        if name not in packages:
            ordered.append(name)
            visited.add(name)
            return
        visiting.add(name)
        for dependency in packages[name][1]["dependencies"]["runtime"]:
            visit(dependency)
        visiting.remove(name)
        visited.add(name)
        ordered.append(name)

    for name in selected:
        visit(name)
    return ordered


def compose_profile(name: str) -> dict[str, Any]:
    profile_path = PACKAGING_ROOT / "profiles" / f"{name}.json"
    profile = read_json(profile_path)
    if profile.get("format") != "auzix-profile-v1" or profile.get("name") != name:
        raise ContractError(f"{profile_path}: invalid profile identity")
    selected = profile.get("packages")
    if not isinstance(selected, list) or not selected or not all(isinstance(item, str) for item in selected):
        raise ContractError(f"{profile_path}: packages must be a non-empty string array")
    packages = load_packages()
    unknown = sorted(set(selected) - packages.keys())
    if unknown:
        raise ContractError(f"{profile_path}: undefined selected packages: {', '.join(unknown)}")
    records = []
    for package_name in dependency_order(selected, packages):
        if package_name not in packages:
            records.append({"name": package_name, "kind": "external-provider"})
            continue
        path, package = packages[package_name]
        records.append({"name": package_name, "apk_name": apk_name(package_name), "version": package["version"], "apk_version": apk_version(package["version"]), "kind": "auzix-package", "definition": str(path.relative_to(REPOSITORY_ROOT)), "definition_sha256": content_sha256(package)})
    lock = {"format": "auzix-profile-lock-v1", "profile": name, "packages": records}
    lock["content_sha256"] = content_sha256(lock)
    return lock
