from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from .activation.base import activate_base
from .bootstrap import bootstrap_apk_tools
from .apk import bootstrap_root, install_apks_chroot, install_lock, install_lock_chroot
from .contracts import ContractError
from .package_graph import compose_profile, load_packages
from .paths import PACKAGING_ROOT
from .preflight import target_preflight
from .fpm import emit_apk
from .repository import compose_index
from .targets import compose_target
from .staging import stage_package
from .layout import activate_layout
from .assembly import assemble_root, emit_and_assemble_root
from .archive_fpm import archive_profile_plan, convert_archive_profile


def emit(value: dict[str, Any], output_name: str | None, label: str) -> None:
    rendered = json.dumps(value, indent=2, sort_keys=True) + "\n"
    if output_name:
        output = Path(output_name)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered, encoding="utf-8")
        digest = value.get("content_sha256") or value.get("target_plan_sha256", "none")
        print(f"PASS {label}={output} sha256={digest}")
    else:
        print(rendered, end="")


def command_validate(_: argparse.Namespace) -> int:
    packages = load_packages()
    profiles = sorted((PACKAGING_ROOT / "profiles").glob("*.json"))
    targets = sorted((PACKAGING_ROOT / "targets").glob("*.json"))
    for profile in profiles:
        compose_profile(profile.stem)
    for target in targets:
        compose_target(target.stem)
    print(f"PASS packages={len(packages)} profiles={len(profiles)} targets={len(targets)}")
    return 0


def command_emit(value: dict[str, Any], output: str | None, label: str) -> int:
    emit(value, output, label)
    return 0


def command_preflight(args: argparse.Namespace) -> int:
    result = target_preflight(args.target)
    emit(result, args.output, "preflight")
    return 0 if result["status"] == "passed" else 2


def command_activate(args: argparse.Namespace) -> int:
    if args.target != "base-netinstall-hdd":
        raise ContractError(f"no activation executor registered for target: {args.target}")
    result = activate_base(Path(args.root), compose_target(args.target))
    emit(result, args.output, "activation")
    return 0


def command_activate_layout(args: argparse.Namespace) -> int:
    result = activate_layout(Path(args.root))
    emit(result, args.output, "layout")
    return 0


def command_bootstrap_apk_tools(args: argparse.Namespace) -> int:
    package = load_packages()["ApkTools"][1]
    installed = bootstrap_apk_tools(package, Path(args.root))
    print(f"PASS apk_tools={installed}")
    return 0


def command_emit_package(args: argparse.Namespace) -> int:
    packages = load_packages()
    if args.package not in packages:
        raise ContractError(f"unknown package: {args.package}")
    argv = emit_apk(packages[args.package][1], Path(args.staged_root), Path(args.output_dir))
    print(json.dumps({"status": "passed", "package": args.package, "argv": argv}, sort_keys=True))
    return 0


def command_stage_package(args: argparse.Namespace) -> int:
    packages = load_packages()
    if args.package not in packages:
        raise ContractError(f"unknown package: {args.package}")
    argv = stage_package(packages[args.package][1], Path(args.staged_root))
    print(json.dumps({"status": "passed", "package": args.package, "argv": argv}, sort_keys=True))
    return 0


def command_emit_profile(args: argparse.Namespace) -> int:
    packages = load_packages()
    lock = compose_profile(args.profile)
    emitted = []
    for record in lock["packages"]:
        package_name = record["name"]
        staged_root = Path(args.staging_root) / package_name
        if args.prepare:
            stage_package(packages[package_name][1], staged_root)
        emit_apk(packages[package_name][1], staged_root, Path(args.output_dir))
        emitted.append(package_name)
    print(json.dumps({"status": "passed", "profile": args.profile, "emitted": emitted}, sort_keys=True))
    return 0


def command_package_surfaces(args: argparse.Namespace) -> int:
    packages = load_packages()
    if args.package not in packages:
        raise ContractError(f"unknown package: {args.package}")
    package = packages[args.package][1]
    surfaces = package.get("payload", {}).get("surfaces") or [package["layout"]["prefix"].replace("${version}", package["version"])]
    print(json.dumps({"package": args.package, "surfaces": surfaces}, sort_keys=True))
    return 0


def command_compose_repository(args: argparse.Namespace) -> int:
    argv = compose_index(Path(args.repository), args.apk_command, allow_untrusted=args.allow_untrusted)
    print(json.dumps({"status": "passed", "repository": args.repository, "argv": argv}, sort_keys=True))
    return 0


def command_install_profile(args: argparse.Namespace) -> int:
    lock = compose_profile(args.profile)
    argv = install_lock(
        lock,
        Path(args.root),
        Path(args.repositories_file),
        apk_command=args.apk_command,
        package_dir=Path(args.package_dir) if args.package_dir else None,
        keys_dir=Path(args.keys_dir) if args.keys_dir else None,
        allow_untrusted=args.allow_untrusted,
    )
    print(json.dumps({"status": "passed", "profile": args.profile, "argv": argv}, sort_keys=True))
    return 0


def command_bootstrap_root(args: argparse.Namespace) -> int:
    lock = compose_profile("bootstrap-base")
    argv = bootstrap_root(
        lock, Path(args.root), Path(args.package_dir),
        apk_command=args.apk_command, allow_untrusted=args.allow_untrusted,
    )
    print(json.dumps({"status": "passed", "profile": "bootstrap-base", "argv": argv}, sort_keys=True))
    return 0


def command_install_profile_chroot(args: argparse.Namespace) -> int:
    lock = compose_profile(args.profile)
    argv = install_lock_chroot(
        lock, Path(args.root), Path(args.package_dir), allow_untrusted=args.allow_untrusted
    )
    print(json.dumps({"status": "passed", "profile": args.profile, "argv": argv}, sort_keys=True))
    return 0


def command_install_apk_directory_chroot(args: argparse.Namespace) -> int:
    packages = sorted(Path(args.package_dir).glob("*.apk"))
    argv = install_apks_chroot(packages, Path(args.root), allow_untrusted=args.allow_untrusted)
    print(json.dumps({"status": "passed", "count": len(packages), "argv": argv}, sort_keys=True))
    return 0


def command_assemble_root(args: argparse.Namespace) -> int:
    result = assemble_root(
        args.profile,
        Path(args.root),
        Path(args.bootstrap_packages),
        Path(args.repository),
        apk_command=args.apk_command,
        allow_untrusted=args.allow_untrusted,
    )
    emit(result, args.output, "assembly")
    return 0


def command_build_root(args: argparse.Namespace) -> int:
    result = emit_and_assemble_root(
        args.profile,
        Path(args.staging_root),
        Path(args.root),
        Path(args.bootstrap_packages),
        Path(args.repository),
        apk_command=args.apk_command,
        allow_untrusted=args.allow_untrusted,
    )
    emit(result, args.output, "build")
    return 0


def command_convert_archive_profile(args: argparse.Namespace) -> int:
    result = convert_archive_profile(
        Path(args.repository), Path(args.profile), Path(args.output_dir), apk_command=args.apk_command
    )
    if args.output:
        emit(result, args.output, "archive_conversion")
    return 0


def command_preflight_archive_profile(args: argparse.Namespace) -> int:
    result = archive_profile_plan(Path(args.repository), Path(args.profile))
    emit(result, args.output, "archive_preflight")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="auzix")
    commands = parser.add_subparsers(dest="command", required=True)
    validate = commands.add_parser("validate")
    validate.set_defaults(func=command_validate)
    profile = commands.add_parser("compose-profile")
    profile.add_argument("profile")
    profile.add_argument("--output")
    profile.set_defaults(func=lambda args: command_emit(compose_profile(args.profile), args.output, "lock"))
    target = commands.add_parser("compose-target")
    target.add_argument("target")
    target.add_argument("--output")
    target.set_defaults(func=lambda args: command_emit(compose_target(args.target), args.output, "target_plan"))
    preflight = commands.add_parser("preflight")
    preflight.add_argument("target")
    preflight.add_argument("--output")
    preflight.set_defaults(func=command_preflight)
    activate = commands.add_parser("activate-target")
    activate.add_argument("target")
    activate.add_argument("root")
    activate.add_argument("--output")
    activate.set_defaults(func=command_activate)
    layout = commands.add_parser("activate-layout")
    layout.add_argument("root")
    layout.add_argument("--output")
    layout.set_defaults(func=command_activate_layout)
    bootstrap = commands.add_parser("bootstrap-apk-tools")
    bootstrap.add_argument("root")
    bootstrap.set_defaults(func=command_bootstrap_apk_tools)
    package = commands.add_parser("emit-package")
    package.add_argument("package")
    package.add_argument("staged_root")
    package.add_argument("output_dir")
    package.set_defaults(func=command_emit_package)
    stage = commands.add_parser("stage-package")
    stage.add_argument("package")
    stage.add_argument("staged_root")
    stage.set_defaults(func=command_stage_package)
    emit_profile = commands.add_parser("emit-profile")
    emit_profile.add_argument("profile")
    emit_profile.add_argument("staging_root")
    emit_profile.add_argument("output_dir")
    emit_profile.add_argument("--prepare", action="store_true")
    emit_profile.set_defaults(func=command_emit_profile)
    surfaces = commands.add_parser("package-surfaces")
    surfaces.add_argument("package")
    surfaces.set_defaults(func=command_package_surfaces)
    repository = commands.add_parser("compose-repository")
    repository.add_argument("repository")
    repository.add_argument("--apk-command", required=True)
    repository.add_argument("--allow-untrusted", action="store_true")
    repository.set_defaults(func=command_compose_repository)
    install = commands.add_parser("install-profile")
    install.add_argument("profile")
    install.add_argument("root")
    install.add_argument("repositories_file")
    install.add_argument("--apk-command", required=True)
    install.add_argument("--keys-dir")
    install.add_argument("--package-dir")
    install.add_argument("--allow-untrusted", action="store_true")
    install.set_defaults(func=command_install_profile)
    bootstrap_root_parser = commands.add_parser("bootstrap-root")
    bootstrap_root_parser.add_argument("root")
    bootstrap_root_parser.add_argument("package_dir")
    bootstrap_root_parser.add_argument("--apk-command", required=True)
    bootstrap_root_parser.add_argument("--allow-untrusted", action="store_true")
    bootstrap_root_parser.set_defaults(func=command_bootstrap_root)
    chroot_install = commands.add_parser("install-profile-chroot")
    chroot_install.add_argument("profile")
    chroot_install.add_argument("root")
    chroot_install.add_argument("package_dir")
    chroot_install.add_argument("--allow-untrusted", action="store_true")
    chroot_install.set_defaults(func=command_install_profile_chroot)
    directory_install = commands.add_parser("install-apk-directory-chroot")
    directory_install.add_argument("root")
    directory_install.add_argument("package_dir")
    directory_install.add_argument("--allow-untrusted", action="store_true")
    directory_install.set_defaults(func=command_install_apk_directory_chroot)
    assembly = commands.add_parser("assemble-root")
    assembly.add_argument("profile")
    assembly.add_argument("root")
    assembly.add_argument("bootstrap_packages")
    assembly.add_argument("repository")
    assembly.add_argument("--apk-command", required=True)
    assembly.add_argument("--allow-untrusted", action="store_true")
    assembly.add_argument("--output")
    assembly.set_defaults(func=command_assemble_root)
    build_root = commands.add_parser("build-root")
    build_root.add_argument("profile")
    build_root.add_argument("staging_root")
    build_root.add_argument("root")
    build_root.add_argument("bootstrap_packages")
    build_root.add_argument("repository")
    build_root.add_argument("--apk-command", required=True)
    build_root.add_argument("--allow-untrusted", action="store_true")
    build_root.add_argument("--output")
    build_root.set_defaults(func=command_build_root)
    archive_preflight = commands.add_parser("preflight-archive-profile")
    archive_preflight.add_argument("repository")
    archive_preflight.add_argument("profile")
    archive_preflight.add_argument("--output")
    archive_preflight.set_defaults(func=command_preflight_archive_profile)
    archive_convert = commands.add_parser("convert-archive-profile")
    archive_convert.add_argument("repository")
    archive_convert.add_argument("profile")
    archive_convert.add_argument("output_dir")
    archive_convert.add_argument("--apk-command", required=True)
    archive_convert.add_argument("--output")
    archive_convert.set_defaults(func=command_convert_archive_profile)
    args = parser.parse_args()
    try:
        return args.func(args)
    except ContractError as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    raise SystemExit(main())
