from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Sequence


def run(argv: Sequence[str], *, cwd: Path | None = None, capture: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(list(argv), cwd=cwd, check=True, text=True, capture_output=capture)
