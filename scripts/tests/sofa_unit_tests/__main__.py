"""Entry point: parse CLI, run tests sequentially, translate outcome to the
spec's exit code (spec §10, §11).

No pytest: this deliberately deviates from SPEC.md/CLAUDE.md's pytest-based
harness (see CLAUDE.md's deviation notice). Discovery, execution, isolation,
and reporting all reuse the same underlying APIs; only the orchestration
(`runner.run_all`) changed.
"""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Optional, Sequence

from . import discovery, runner
from .config import EXIT_USAGE_ERROR, Config, UsageError, exit_code_for_outcome, parse_args


def _list_only(cfg: Config) -> int:
    bin_dir = (cfg.build_dir / "bin").resolve()
    binaries = discovery.discover_binaries(cfg.build_dir)

    for binary in binaries:
        name = discovery.test_name_for_path(binary)
        if cfg.filter is not None and not cfg.filter.search(name):
            continue
        if cfg.exclude is not None and cfg.exclude.search(name):
            continue
        print(binary.relative_to(bin_dir))
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    if argv is None:
        argv = sys.argv[1:]

    try:
        cfg = parse_args(argv)
    except UsageError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_USAGE_ERROR

    if cfg.list_only:
        try:
            return _list_only(cfg)
        except UsageError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return EXIT_USAGE_ERROR

    try:
        counts = runner.run_all(cfg)
    except UsageError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_USAGE_ERROR

    return exit_code_for_outcome(any_crash=counts.crashes > 0, any_failure=counts.failures > 0)


if __name__ == "__main__":
    sys.exit(main())
