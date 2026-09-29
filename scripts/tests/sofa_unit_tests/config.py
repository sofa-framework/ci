"""CLI parsing, validation, and exit-code mapping (spec §2, §10, §11)."""
from __future__ import annotations

import argparse
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence

EXIT_OK = 0
EXIT_FAILURE = 1
EXIT_CRASH = 2
EXIT_USAGE_ERROR = 3


class UsageError(Exception):
    """A usage/configuration error (spec §11, exit code 3)."""


@dataclass(frozen=True)
class Config:
    build_dir: Path
    results_dir: Path
    threads: int
    timeout: int
    filter: Optional[re.Pattern]
    exclude: Optional[re.Pattern]
    list_only: bool
    verbose: bool


def clamp_threads(threads: int) -> int:
    """Clamp to the machine's CPU count when it can be determined (spec §10)."""
    cpu_count = os.cpu_count()
    if cpu_count is not None and threads > cpu_count:
        return cpu_count
    return threads


def _compile_regex(pattern: Optional[str], flag_name: str) -> Optional[re.Pattern]:
    if pattern is None:
        return None
    try:
        return re.compile(pattern)
    except re.error as exc:
        raise UsageError(f"invalid regex for {flag_name}: {pattern!r} ({exc})") from exc


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="sofa-unit-tests")
    parser.add_argument("--build-dir", default=None)
    parser.add_argument("--results-dir", default=None)
    parser.add_argument("-j", "--jobs", type=int, dest="threads", default=1)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--filter", default=None)
    parser.add_argument("--exclude", default=None)
    parser.add_argument("--list-only", action="store_true", default=False)
    parser.add_argument("--verbose", type=int, default=0)
    return parser


def parse_args(argv: Sequence[str]) -> Config:
    ns = _build_parser().parse_args(argv)

    if ns.build_dir is None:
        raise UsageError("--build-dir is required")
    if ns.results_dir is None:
        raise UsageError("--results-dir is required")

    build_dir = Path(ns.build_dir).resolve()
    results_dir = Path(ns.results_dir).resolve()

    if ns.threads <= 0:
        raise UsageError(f"--threads must be a positive integer, got {ns.threads}")

    return Config(
        build_dir=build_dir,
        results_dir=results_dir,
        threads=clamp_threads(ns.threads),
        timeout=ns.timeout,
        filter=_compile_regex(ns.filter, "--filter"),
        exclude=_compile_regex(ns.exclude, "--exclude"),
        list_only=ns.list_only,
        verbose=ns.verbose
    )


def exit_code_for_outcome(*, any_crash: bool, any_failure: bool) -> int:
    """Map run outcome to the tool's exit code, crash outranking failure (spec §11)."""
    if any_crash:
        return EXIT_CRASH
    if any_failure:
        return EXIT_FAILURE
    return EXIT_OK
