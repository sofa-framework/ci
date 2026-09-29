"""Write per-scene logs and summary files under test_results_dir (spec §7).

The two halves of §7 are exposed separately because the runner uses them from
different threads.  `write_scene_log` is called by the worker that ran the
scene: one file per scene, disjoint paths, so concurrent calls never meet.
`record_summary_entries` appends to the three shared files at the root and is
therefore called single-threaded, once the run is over.  `record_scene_result`
composes both for callers that have no concurrency to worry about.
"""

from pathlib import Path
from typing import Sequence

from .classify import Classification, RunResult
from .discovery import ScenePlan
from .paths import posix_str, scene_log_path
from .utils import SceneOutcome

# Summary files are zero-byte when their category has no entries (documented choice).
_SUMMARY_FILES = ("scene_errors.txt", "scene_warnings.txt", "scene_crashes.txt")


def initialize_report_dir(test_results_dir: Path) -> None:
    """Create test_results_dir and empty summary files (§7.2, §12.1).

    Must be called once before any scene results are recorded. Creates
    zero-byte summary files so that all three always exist after a run.
    """
    test_results_dir.mkdir(parents=True, exist_ok=True)
    for name in _SUMMARY_FILES:
        (test_results_dir / name).write_text("", encoding="utf-8")


def _write_log(test_results_dir: Path, plan: ScenePlan, content: str) -> Path:
    """Write content to the scene's .log file and return its path (§7.1)."""
    log_path = scene_log_path(test_results_dir, plan.bucket, plan.bucket_subpath)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(content, encoding="utf-8")
    return log_path


def _append_summary_entry(
    summary_file: Path,
    scene_path: Path,
    log_rel: Path,
    matching_lines: tuple[str, ...],
) -> None:
    """Append one entry to a summary file in the §7.2 format."""
    with summary_file.open("a", encoding="utf-8") as f:
        f.write(f"{posix_str(scene_path)} : {posix_str(log_rel)}\n")
        for line in matching_lines:
            f.write(f"{line}\n")
        f.write("\n")


def write_scene_log(
    test_results_dir: Path,
    plan: ScenePlan,
    result: RunResult | None,
) -> None:
    """Write the .log file of one scene (§7.1).

    Safe to call from a worker thread: the path is derived from the scene's own
    bucket and subpath, so no two scenes write to the same file.

    When result is None (add_target_missing), the log holds the single line
    'file not found' (§3.5.2).

    @param plan Scene the log belongs to.
    @param result Its captured output, or None when it never launched.
    """
    if plan.add_target_missing or result is None:
        _write_log(test_results_dir, plan, "file not found")
        return

    _write_log(test_results_dir, plan, result.stdout + result.stderr)


def record_summary_entries(
    test_results_dir: Path,
    plan: ScenePlan,
    result: RunResult | None,
    classification: Classification | None,
) -> None:
    """Append one scene's entries to the shared summary files (§7.2).

    The three files at the root of the results tree are shared by every scene,
    so this must be called from a single thread.  Nothing is appended for a
    scene that never launched, nor for one that was not classified.

    @param plan Scene the entries describe.
    @param result Its captured output, or None when it never launched.
    @param classification Verdict on that output, or None when there is none.
    """
    if plan.add_target_missing or result is None or classification is None:
        return

    log_path = scene_log_path(test_results_dir, plan.bucket, plan.bucket_subpath)
    log_rel = log_path.relative_to(test_results_dir)

    if classification.is_error:
        _append_summary_entry(
            test_results_dir / "scene_errors.txt",
            plan.path,
            log_rel,
            classification.error_lines,
        )
    if classification.is_warning:
        _append_summary_entry(
            test_results_dir / "scene_warnings.txt",
            plan.path,
            log_rel,
            classification.warning_lines,
        )
    if classification.is_crash:
        _append_summary_entry(
            test_results_dir / "scene_crashes.txt",
            plan.path,
            log_rel,
            classification.crash_lines,
        )


def record_scene_result(
    test_results_dir: Path,
    plan: ScenePlan,
    result: RunResult | None,
    classification: Classification | None,
) -> None:
    """Write the log file and update the summary files for one scene (§7).

    Both halves in one call, for a caller running scenes one at a time.  The
    runner splits them instead, so that only the summary half is serialised.
    """
    write_scene_log(test_results_dir, plan, result)
    record_summary_entries(test_results_dir, plan, result, classification)


def _write_summary_txt(path: Path, outcomes: Sequence[SceneOutcome], duration_second : float) -> None:

    failed = sum(1 for o in outcomes if o.failed)
    crashed = sum(1 for o in outcomes if o.crashed)
    skipped = sum(1 for o in outcomes if o.skipped)


    lines = [
        f"test_suite={1}",
        f"test_total={len(outcomes)}",
        f"disabled_tests={skipped}",
        f"failures={failed}",
        f"crashes={crashed}",
        f"duration={duration_second:.3f}",
    ]
    path.write_text("\n".join(lines) + "\n")
