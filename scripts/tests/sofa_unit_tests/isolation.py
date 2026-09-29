"""Crash isolation: enumerate and re-run sub-tests individually (spec §9)."""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import List, Optional, Tuple

from . import classify, execution, paths


class SubtestStatus(Enum):
    PASSED = "passed"
    FAILED = "failed"
    CRASHED = "crashed"
    ZERO_MATCH = "zero_match"


@dataclass(frozen=True)
class SubtestOutcome:
    ordinal: int
    suite: str
    case: str
    status: SubtestStatus
    parsed: Optional[classify.ParsedReport]
    run_outcome: execution.RunOutcome


@dataclass(frozen=True)
class IsolationResult:
    enumerable: bool
    subtests: List[SubtestOutcome]

    @property
    def any_crash(self) -> bool:
        if not self.enumerable:
            return True
        return any(s.status is SubtestStatus.CRASHED for s in self.subtests)


def parse_gtest_list_tests(output: str) -> List[Tuple[str, str]]:
    """Parse `--gtest_list_tests` output into ordered (suite, case) pairs (spec §9.1)."""
    result: List[Tuple[str, str]] = []
    current_suite: Optional[str] = None
    for raw_line in output.splitlines():
        if not raw_line.strip():
            continue
        if not raw_line[:1].isspace():
            suite = raw_line.strip()
            if suite.endswith("."):
                suite = suite[:-1]
            current_suite = suite
            continue
        if current_suite is None:
            continue
        case = raw_line.strip()
        hash_idx = case.find("#")
        if hash_idx != -1:
            case = case[:hash_idx].rstrip()
        result.append((current_suite, case))
    return result


def enumerate_subtests(
    binary: Path, *, timeout, is_windows: Optional[bool] = None
) -> Optional[List[Tuple[str, str]]]:
    """Run --gtest_list_tests; None if the binary crashes/times out enumerating (spec §9.3)."""
    argv = execution.build_argv(binary, gtest_list_tests=True)
    outcome = execution.run_binary(argv, timeout=timeout)
    if outcome.timed_out or outcome.returncode != 0:
        return None
    return parse_gtest_list_tests(outcome.output.decode(errors="replace"))


def run_subtest(
    binary: Path,
    suite: str,
    case: str,
    ordinal: int,
    *,
    subtest_directory: Path,
    timeout,
    is_windows: Optional[bool] = None,
) -> SubtestOutcome:
    """Re-run one sub-test filtered, recording its own artifacts (spec §9.2)."""
    gtest_filter = f"{suite}.{case}"
    run_outcome = execution.execute_and_record(
        binary,
        output_path=paths.output_path(subtest_directory),
        command_line_path=paths.command_line_path(subtest_directory),
        exit_status_path=paths.exit_status_path(subtest_directory),
        gtest_output_xml=paths.report_xml_path(subtest_directory),
        gtest_filter=gtest_filter,
        timeout=timeout,
        is_windows=is_windows,
    )
    parsed = classify.parse_report(paths.report_xml_path(subtest_directory))

    if parsed is None:
        status = SubtestStatus.CRASHED
    elif len(parsed.testcases) == 0:
        status = SubtestStatus.ZERO_MATCH
    elif parsed.passed:
        status = SubtestStatus.PASSED
    else:
        status = SubtestStatus.FAILED

    return SubtestOutcome(
        ordinal=ordinal,
        suite=suite,
        case=case,
        status=status,
        parsed=parsed,
        run_outcome=run_outcome,
    )


def isolate(
    binary: Path,
    *,
    binary_dir: Path,
    timeout,
    is_windows: Optional[bool] = None,
) -> IsolationResult:
    """Enumerate and re-run every sub-test, continuing through the whole list (spec §9)."""
    subtest_list = enumerate_subtests(binary, timeout=timeout, is_windows=is_windows)
    if subtest_list is None:
        return IsolationResult(enumerable=False, subtests=[])

    outcomes = []
    for ordinal, (suite, case) in enumerate(subtest_list, start=1):
        subtest_directory = paths.subtest_dir(binary_dir, suite, case)
        outcome = run_subtest(
            binary,
            suite,
            case,
            ordinal,
            subtest_directory=subtest_directory,
            timeout=timeout,
            is_windows=is_windows,
        )
        outcomes.append(outcome)
    return IsolationResult(enumerable=True, subtests=outcomes)
