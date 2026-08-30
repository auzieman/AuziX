from __future__ import annotations

from pathlib import Path

from .contracts import ContractError
from .process import run


def compose_index(repository: Path, apk_command: str, *, allow_untrusted: bool = False, dry_run: bool = False) -> list[str]:
    repository = repository.resolve()
    packages = sorted(repository.glob("*.apk"))
    if not packages:
        raise ContractError(f"repository contains no APK packages: {repository}")
    command = Path(apk_command).resolve()
    if not command.is_file():
        raise ContractError(f"apk-tools command is not available: {command}")
    output = repository / "APKINDEX.tar.gz"
    argv = [str(command)]
    if allow_untrusted:
        argv.append("--allow-untrusted")
    argv.extend(["index", "--output", str(output), *map(str, packages)])
    if not dry_run:
        run(argv)
    return argv
