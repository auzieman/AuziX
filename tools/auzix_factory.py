#!/usr/bin/env python3
"""Compatibility entry point; new callers should use `python3 -m auzix`."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from auzix.cli import main


raise SystemExit(main())
