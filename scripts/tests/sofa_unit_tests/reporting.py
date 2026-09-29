"""Build failed_tests/crashed_tests/summary.txt from on-disk state (spec §8).

Called once, at session end, on the main/master process. Every count and every
block is derived by re-reading the results tree — never from state accumulated
in worker-process memory (xdist-safe, per CLAUDE.md §6).
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence, Tuple, Dict

from . import classify, isolation, paths

@dataclass(frozen=True)
class Counts:
    test_suite: int
    test_total: int
    disabled_tests: int
    failures: int
    crashes: int
    duration: int


def _read_exit_status(directory: Path) -> str:
    return paths.exit_status_path(directory).read_text().strip()


def _crash_message(subject: str, exit_status_text: str) -> str:
    if exit_status_text == "timeout":
        return f"[CRASH] {subject} ended with timeout"
    return f"[CRASH] {subject} ended with code {exit_status_text}"


def _render_type_a(test_name: str, tc: classify.TestCaseResult) -> str:
    body = "\n".join(tc.failure_texts)
    return "\n".join(
        [
            "---",
            f"{test_name}:",
            f" - Test suite: '{tc.suite}'",
            f" - Test name: '{tc.name}'",
            body,
            "---",
        ]
    )


def _render_type_b(test_name: str, ordinal: int, tc: classify.TestCaseResult) -> str:
    body = "\n".join(tc.failure_texts)
    return "\n".join(
        [
            "---",
            f"{test_name}_subtest{ordinal:03d}:",
            f" - Test suite: '{tc.suite}'",
            f" - Test name: '{tc.name}'",
            body,
            "---",
        ]
    )


def _render_type_c(test_name: str, ordinal: int, suite: str, case: str, exit_status_text: str) -> str:
    crash_line = _crash_message(f"{suite}.{case}", exit_status_text)
    return "\n".join(
        [
            "---",
            f"{test_name}_subtest{ordinal:03d}:",
            f" - Test suite: '{suite}'",
            f" - Test name: '{case}'",
            crash_line,
            "---",
        ]
    )


def _render_type_d(test_name: str, exit_status_text: str) -> str:
    crash_line = _crash_message(test_name, exit_status_text)
    return "\n".join(["---", f"{test_name}:", crash_line, "---"])


def _write_summary_file(path: Path, blocks: List[str]) -> None:
    if not blocks:
        if path.exists():
            path.unlink()
        return
    path.write_text("\n".join(blocks) + "\n")


def _write_summary_txt(path: Path, counts: Counts) -> None:
    lines = [
        f"test_suite={counts.test_suite}",
        f"test_total={counts.test_total}",
        f"disabled_tests={counts.disabled_tests}",
        f"failures={counts.failures}",
        f"crashes={counts.crashes}",
        f"duration={counts.duration}",
    ]
    path.write_text("\n".join(lines) + "\n")


def getInsights(
    binary_report_dir,
    test_name,
    binary_path,
    timeout,
    is_windows: Optional[bool] = None
)  -> tuple(List[str], List[str], List[str], List[str], int, int, int):

    failed_blocks: List[str] = []
    crashed_blocks: List[str] = []


    failed_tests_names: List[str] = []
    crashed_tests_names: List[str] = []

    top_report = classify.parse_report(paths.report_xml_path(binary_report_dir))

    test_total = 0
    disabled_tests = 0
    failures = 0

    if top_report is not None:
        test_total += top_report.tests
        disabled_tests += top_report.disabled
        failures += top_report.failures + top_report.errors
        for tc in top_report.testcases:
            if tc.failed:
                failed_blocks.append(_render_type_a(test_name, tc))
                failed_tests_names.append(tc.name)
        return failed_blocks, crashed_blocks, failed_tests_names, crashed_tests_names, test_total, disabled_tests, failures


    subtests_root = paths.subtests_dir(binary_report_dir)
    was_enumerable = subtests_root.is_dir() and any(subtests_root.iterdir())

    enumerated = None
    if was_enumerable:
        enumerated = isolation.enumerate_subtests(
            binary_path, timeout=timeout, is_windows=is_windows
        )

    if enumerated is None:
        exit_status_text = _read_exit_status(binary_report_dir)
        crashed_blocks.append(_render_type_d(test_name, exit_status_text))
        ## Nothing ot add to crashed_tests_names as in this case it is the full test suite that crashed.
        return failed_blocks, crashed_blocks, failed_tests_names, crashed_tests_names, test_total, disabled_tests, failures


    for ordinal, (suite, case) in enumerate(enumerated, start=1):
        subtest_directory = paths.subtest_dir(binary_report_dir, suite, case)
        parsed = classify.parse_report(paths.report_xml_path(subtest_directory))

        if parsed is None:
            exit_status_text = _read_exit_status(subtest_directory)
            crashed_blocks.append(
                _render_type_c(test_name, ordinal, suite, case, exit_status_text)
            )
            crashed_tests_names.append(case)
            continue


        if len(parsed.testcases) == 0:
            continue


        test_total += parsed.tests
        disabled_tests += parsed.disabled
        failures += parsed.failures + parsed.errors
        for tc in parsed.testcases:
            if tc.failed:
                failed_blocks.append(_render_type_b(test_name, ordinal, tc))
                failed_tests_names.append(tc.name)


    return failed_blocks, crashed_blocks, failed_tests_names, crashed_tests_names, test_total, disabled_tests, failures

def build_reports(
    results_dir: Path,
    executed: Sequence[Tuple[str, Path]],
    *,
    duration_seconds: float,
    timeout,
    is_windows: Optional[bool] = None,
) -> tuple(Counts, List[str], List[str]):
    """Build failed_tests, crashed_tests, and summary.txt for one completed run (spec §8)."""
    results_dir = Path(results_dir)
    results_dir.mkdir(parents=True, exist_ok=True)

    failed_tests_names: Dict = {}
    crashed_tests_names: Dict = {}
    failed_blocks: List[str] = []
    crashed_blocks: List[str] = []
    test_total = 0
    disabled_tests = 0
    failures = 0


    for test_name, binary_path in executed:
        binary_report_dir = paths.binary_dir(results_dir, test_name)

        temp_failed, temp_crash, failed_case_names, crashed_case_names, add_test_total, add_disabled_tests, add_failures = getInsights(binary_report_dir, test_name, binary_path, timeout, is_windows)

        if len(temp_failed):
            failed_tests_names[test_name] = failed_case_names
        if len(temp_crash):
            crashed_tests_names[test_name] = crashed_case_names


        failed_blocks.extend(temp_failed)
        crashed_blocks.extend(temp_crash)
        test_total += add_test_total
        disabled_tests += add_disabled_tests
        failures += add_failures

    _write_summary_file(paths.failed_tests_path(results_dir), failed_blocks)
    _write_summary_file(paths.crashed_tests_path(results_dir), crashed_blocks)

    counts = Counts(
        test_suite=len(executed),
        test_total=test_total,
        disabled_tests=disabled_tests,
        failures=failures,
        crashes=len(crashed_blocks),
        duration=int(duration_seconds),
    )
    _write_summary_txt(paths.summary_txt_path(results_dir), counts)
    return counts, failed_tests_names, crashed_tests_names
