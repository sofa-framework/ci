"""Command-line entry point: parse the arguments, then list or run the scenes.

Usage:
    python -m sofa_scene_tests \\
        --src-dir /path/to/sofa \\
        --build-dir /path/to/sofa/.pixi/envs/supported-plugins-dev/sofa-build \\
        --results-dir ../scene-tests-results

Kept as thin as `sofa_unit_tests/__main__.py`: everything but the argument
parsing and the `--list-only` early return lives in `runner.py`.
"""

import argparse
import sys
from typing import Sequence

from sofa_scene_tests import runner
from sofa_scene_tests.config import build_config

EXIT_OK = 0
EXIT_FAILURE = 1


def build_parser() -> argparse.ArgumentParser:
    """Build the argument parser. Flags mirror the §2 option set.

    Flag names match `sofa-unit-tests` wherever the purpose is the same; the
    spec's original spellings (`--test-results-dir`, `--timeout-sec`,
    `--collect-only`) stay accepted as aliases.
    """
    parser = argparse.ArgumentParser(
        prog="python -m sofa_scene_tests",
        description="Run every discovered SOFA scene through runSofa and report.",
    )
    parser.add_argument(
        "--src-dir",
        default=None,
        metavar="DIR",
        help="SOFA source tree root (SOFA_SCENE_TESTS_SRC_DIR)",
    )
    parser.add_argument(
        "--build-dir",
        default=None,
        metavar="DIR",
        help="SOFA build tree root (SOFA_SCENE_TESTS_BUILD_DIR)",
    )
    parser.add_argument(
        "--results-dir",
        "--test-results-dir",
        dest="results_dir",
        default=None,
        metavar="DIR",
        help="Output root for logs and summaries (SOFA_SCENE_TESTS_RESULTS)",
    )
    parser.add_argument(
        "-j",
        "--jobs",
        dest="jobs",
        type=int,
        default=1,
        metavar="N",
        help="Number of worker threads running scenes concurrently (default: 1)",
    )
    parser.add_argument(
        "--timesteps",
        default=100,
        type=int,
        metavar="N",
        help="Number of timesteps passed to runSofa -n (default: 100)",
    )
    parser.add_argument(
        "--timeout",
        "--timeout-sec",
        dest="timeout",
        default=30,
        type=int,
        metavar="S",
        help="Per-scene kill timeout in seconds (default: 30)",
    )
    parser.add_argument(
        "--runsofa",
        default=None,
        metavar="BIN",
        help="Absolute path to runSofa binary (default: <BUILD_DIR>/bin/runSofa)",
    )
    parser.add_argument(
        "-k",
        "--filter",
        action="append",
        default=None,
        dest="filters",
        metavar="PATTERN",
        help=(
            "Run only scenes whose ID matches PATTERN. A pattern containing "
            "'*' or '?' is matched as a glob against the whole ID; otherwise "
            "it is a plain substring match. Repeatable — a scene runs if it "
            "matches any pattern."
        ),
    )
    parser.add_argument(
        "--exclude",
        action="append",
        default=None,
        dest="excludes",
        metavar="PATTERN",
        help=(
            "Skip scenes whose ID matches PATTERN, using the same matching "
            "rules as --filter. Applied after --filter. Repeatable."
        ),
    )
    parser.add_argument(
        "--list-only",
        "--collect-only",
        dest="list_only",
        action="store_true",
        default=False,
        help="List the selected scene IDs and exit without launching runSofa",
    )
    parser.add_argument(
        "--verbose",
        type=int,
        default=0,
        metavar="LEVEL",
        help=(
            "0 for the status line only, 1 to append the failure/skip block, "
            "2 to append the raw runSofa output (default: 0)"
        ),
    )
    return parser


def _list_only(config) -> int:
    """Print the selected scene IDs without running them.

    @param config Configuration providing the source tree and the filter/exclude patterns.
    @return 0, this listing never failing on its own.
    """
    plans, discovered = runner.selected_scenes(config)

    for plan in plans:
        print(plan.test_id)
    if config.filters or config.excludes:
        print(f"{len(plans)} of {discovered} scene(s) selected.")
    else:
        print(f"{len(plans)} scene(s) discovered.")
    return EXIT_OK


def main(argv: Sequence[str] | None = None) -> int:
    """Entry point of the tool: parse the arguments, then list or run the scenes.

    @param argv Argument list excluding the program name; defaults to sys.argv[1:].
    @return The process exit code: 0 on success, 1 on any failure or empty selection.
    """
    if argv is None:
        argv = sys.argv[1:]

    args = build_parser().parse_args(argv)

    config = build_config(
        src_dir_raw=args.src_dir,
        build_dir_raw=args.build_dir,
        test_results_dir_raw=args.results_dir,
        timesteps=args.timesteps,
        timeout_sec=args.timeout,
        runsofa_raw=args.runsofa,
        threads=args.jobs,
        verbose=args.verbose,
        filters=args.filters,
        excludes=args.excludes,
    )

    if args.list_only:
        return _list_only(config)

    outcomes = runner.run_all(config)
    if not outcomes:
        return EXIT_FAILURE

    return EXIT_FAILURE if any(o.failed or o.crashed for o in outcomes) else EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
