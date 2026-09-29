"""Recursive test-binary discovery under <build-dir>/bin (spec §3)."""
from __future__ import annotations

import os
from pathlib import Path
from typing import List, Optional

from .config import UsageError

_SUFFIXES = ("_test", "_simutest", ".Tests", "_testd", "_simutestd", ".Testsd")


def _strip_trailing_exe(name: str) -> str:
    if name.endswith(".exe"):
        return name[: -len(".exe")]
    return name


def test_name_for_path(path: Path) -> str:
    """The <test_name> for a discovered binary (spec §3.4)."""
    return _strip_trailing_exe(path.name)


def _matches_suffix(name: str, is_windows: bool) -> bool:
    check_name = _strip_trailing_exe(name) if is_windows else name
    return any(
        check_name.endswith(suffix) and len(check_name) > len(suffix)
        for suffix in _SUFFIXES
    )


def _is_executable(path: Path, is_windows: bool) -> bool:
    if is_windows:
        return path.name.endswith(".exe")
    resolved = path.resolve()
    return resolved.is_file() and os.access(resolved, os.X_OK)


def discover_binaries(build_dir: Path, *, is_windows: Optional[bool] = None) -> List[Path]:
    """Discover GoogleTest binaries under <build-dir>/bin, recursively (spec §3)."""
    if is_windows is None:
        is_windows = os.name == "nt"

    bin_dir = Path(build_dir) / "bin"
    if not bin_dir.is_dir():
        raise UsageError(f"bin directory not found under --build-dir: {bin_dir}")

    seen = set()
    found: List[Path] = []
    for candidate in sorted(bin_dir.rglob("*")):
        if not candidate.is_file():
            continue
        if not _matches_suffix(candidate.name, is_windows):
            continue
        if not _is_executable(candidate, is_windows):
            continue
        resolved = candidate.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        found.append(resolved)
    return found
