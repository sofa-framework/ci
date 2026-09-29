"""Parse CLI + env vars into a frozen Config dataclass (spec §2, §9.1, §11)."""

import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence


@dataclass(frozen=True)
class Config:
    src_dir: Path
    build_dir: Path
    test_results_dir: Path
    timesteps: int
    timeout_sec: int
    runsofa: Path
    # Front-end options, mirroring sofa_unit_tests.config.Config.
    threads: int = 1
    verbose: int = 0
    filters: tuple[str, ...] = ()
    excludes: tuple[str, ...] = ()


def clamp_threads(threads: int) -> int:
    """Cap a requested thread count to the number of available CPUs.

    @param threads Thread count asked for by the user.
    @return The requested count, or the CPU count when it is exceeded.
    """
    cpu_count = os.cpu_count()
    if cpu_count is not None and threads > cpu_count:
        return cpu_count
    return threads


def _fail(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def _resolve_runsofa(runsofa_raw: str | None, build_dir: Path) -> Path:
    """Resolve the runSofa binary path per §5.2.1.

    Never falls back silently: if --runsofa is given and invalid, errors out
    rather than trying the default.
    """
    if runsofa_raw is not None:
        p = Path(runsofa_raw)
        if not p.is_absolute():
            _fail(
                f"--runsofa requires an absolute path; got: {runsofa_raw!r}. "
                "SOFA.SceneTests does not resolve relative paths against cwd."
            )
        if not p.exists():
            _fail(f"--runsofa path does not exist: {p}")
        if not p.is_file():
            _fail(f"--runsofa path is not a regular file: {p}")
        if sys.platform != "win32" and not os.access(p, os.X_OK):
            _fail(f"--runsofa path is not executable: {p}")
        return p

    exe_name = "runSofa.exe" if sys.platform == "win32" else "runSofa"
    default_path = build_dir / "bin" / exe_name
    if not default_path.exists():
        _fail(
            f"Default runSofa binary not found at {default_path}. "
            "Pass --runsofa <absolute-path> to override."
        )
    if not default_path.is_file():
        _fail(f"Default runSofa is not a regular file: {default_path}")
    if sys.platform != "win32" and not os.access(default_path, os.X_OK):
        _fail(f"Default runSofa is not executable: {default_path}")
    return default_path


def build_config(
    *,
    src_dir_raw: str | None = None,
    build_dir_raw: str | None = None,
    test_results_dir_raw: str | None = None,
    timesteps: int = 100,
    timeout_sec: int = 30,
    runsofa_raw: str | None = None,
    threads: int = 1,
    verbose: int = 0,
    filters: Sequence[str] | None = None,
    excludes: Sequence[str] | None = None,
    environ: Mapping[str, str] | None = None,
) -> Config:
    """Build and validate a Config from CLI values + environment variables.

    CLI parameters (*_raw args) take precedence over environment variables,
    which take precedence over defaults.  Calls sys.exit(1) on any error.
    """
    if environ is None:
        environ = os.environ

    src_str = src_dir_raw or environ.get("SOFA_SCENE_TESTS_SRC_DIR")
    build_str = build_dir_raw or environ.get("SOFA_SCENE_TESTS_BUILD_DIR")
    results_str = test_results_dir_raw or environ.get("SOFA_SCENE_TESTS_RESULTS")

    if not src_str:
        _fail(
            "src_dir is required. "
            "Provide --src-dir or set SOFA_SCENE_TESTS_SRC_DIR."
        )
    if not build_str:
        _fail(
            "build_dir is required. "
            "Provide --build-dir or set SOFA_SCENE_TESTS_BUILD_DIR."
        )
    if not results_str:
        _fail(
            "test_results_dir is required. "
            "Provide --test-results-dir or set SOFA_SCENE_TESTS_RESULTS."
        )

    src_dir = Path(src_str).resolve()
    build_dir = Path(build_str).resolve()
    test_results_dir = Path(results_str).resolve()

    runsofa = _resolve_runsofa(runsofa_raw, build_dir)

    if threads <= 0:
        _fail(f"--threads must be a positive integer, got {threads}")

    return Config(
        src_dir=src_dir,
        build_dir=build_dir,
        test_results_dir=test_results_dir,
        timesteps=timesteps,
        timeout_sec=timeout_sec,
        runsofa=runsofa,
        threads=clamp_threads(threads),
        verbose=verbose,
        filters=tuple(filters or ()),
        excludes=tuple(excludes or ()),
    )
