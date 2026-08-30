from __future__ import annotations

from pathlib import Path
import subprocess

from .contracts import ContractError


ALIASES = {
    "/bin": "/System/Compatibility/bin",
    "/etc": "/System/Settings",
    "/home": "/Users",
    "/lib": "/System/Compatibility/lib",
    "/lib64": "/System/Compatibility/lib64",
    "/opt": "/Programs",
    "/root": "/Users/root",
    "/sbin": "/System/Compatibility/sbin",
    "/System/Libraries": "/Libraries",
    "/tmp": "/Work/Temp",
    "/usr": "/System/Compatibility/usr",
    "/var": "/System/State",
}

COMMAND_ALIASES = {
    "/System/Compatibility/bin/apk": "/Programs/ApkTools/current/Commands/apk",
    "/System/Compatibility/bin/busybox": "/Programs/BusyBox/current/Commands/busybox",
    "/System/Compatibility/bin/sh": "/Programs/BusyBox/current/Commands/busybox",
}


def rooted(root: Path, absolute: str) -> Path:
    if not absolute.startswith("/"):
        raise ContractError(f"layout path is not absolute: {absolute}")
    return root / absolute.lstrip("/")


def merge_directory(root: Path, source_absolute: str, target_absolute: str) -> None:
    source = rooted(root, source_absolute)
    if not source.is_dir() or source.is_symlink():
        return
    target = rooted(root, target_absolute)
    target.mkdir(parents=True, exist_ok=True)

    def merge_tree(source_directory: Path, target_directory: Path) -> None:
        for source_child in source_directory.iterdir():
            destination = target_directory / source_child.name
            if (
                source_child.is_dir() and not source_child.is_symlink()
                and destination.is_dir() and not destination.is_symlink()
            ):
                merge_tree(source_child, destination)
                source_child.rmdir()
                continue
            if destination.exists() or destination.is_symlink():
                raise ContractError(f"layout merge target already exists: {destination}")
            source_child.rename(destination)

    merge_tree(source, target)
    source.rmdir()


def link(root: Path, absolute: str, target: str) -> None:
    path = rooted(root, absolute)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_dir() and not path.is_symlink():
        merge_directory(root, absolute, target)
    if path.exists() or path.is_symlink():
        path.unlink()
    path.symlink_to(target)


def activate_layout(root: Path) -> dict[str, object]:
    root = root.resolve()
    for absolute in ("/Libraries/Packages", "/Libraries/Private"):
        rooted(root, absolute).mkdir(parents=True, exist_ok=True)
    relocated_libraries: list[str] = []
    programs = rooted(root, "/Programs")
    if programs.is_dir():
        for source in sorted(programs.glob("Lib*")):
            if source.is_symlink() or not source.is_dir():
                continue
            destination = rooted(root, f"/Libraries/Packages/{source.name}")
            if destination.exists() or destination.is_symlink():
                raise ContractError(f"library relocation target already exists: {destination}")
            source.rename(destination)
            source.symlink_to(f"/Libraries/Packages/{source.name}")
            relocated_libraries.append(source.name)
    merge_directory(root, "/lib/apk", "/System/State/apk")
    merge_directory(root, "/etc/apk", "/System/Settings/apk")
    merge_directory(root, "/var", "/System/State")
    for absolute in ALIASES:
        rooted(root, ALIASES[absolute]).mkdir(parents=True, exist_ok=True)
    apk_link = rooted(root, "/System/Compatibility/lib/apk")
    if not apk_link.exists() and not apk_link.is_symlink():
        apk_link.symlink_to("/System/State/apk")
    for absolute, target in ALIASES.items():
        link(root, absolute, target)
    rooted(root, "/Libraries/Runtime").mkdir(parents=True, exist_ok=True)
    for absolute, target in COMMAND_ALIASES.items():
        link(root, absolute, target)
    busybox = "/Programs/BusyBox/current/Commands/busybox"
    published_applets: list[str] = []
    if rooted(root, "/Programs/BusyBox").exists():
        result = subprocess.run(
            ["chroot", str(root), busybox, "--list"],
            check=True,
            capture_output=True,
            text=True,
        )
        command_dir = rooted(root, "/System/Compatibility/bin")
        for applet in result.stdout.splitlines():
            if not applet or "/" in applet:
                continue
            command = command_dir / applet
            if command.exists() or command.is_symlink():
                continue
            command.symlink_to(busybox)
            published_applets.append(applet)
    return {
        "status": "passed",
        "aliases": {**ALIASES, **COMMAND_ALIASES},
        "apk_database": "/System/State/apk",
        "busybox_applets_published": published_applets,
        "libraries_relocated": relocated_libraries,
    }
