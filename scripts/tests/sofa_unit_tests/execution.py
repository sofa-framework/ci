"""Launch one binary or one filtered sub-test as a subprocess (spec §5, §6.1, §7.3, §7.4)."""
from __future__ import annotations

import os
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence


@dataclass(frozen=True)
class RunOutcome:
    argv: List[str]
    output: bytes
    timed_out: bool
    returncode: Optional[int]


def build_argv(
    binary: Path,
    *,
    gtest_filter: Optional[str] = None,
    gtest_output_xml: Optional[Path] = None,
    gtest_list_tests: bool = False,
) -> List[str]:
    argv = [str(binary)]
    if gtest_list_tests:
        argv.append("--gtest_list_tests")
    if gtest_filter is not None:
        argv.append(f"--gtest_filter={gtest_filter}")
    if gtest_output_xml is not None:
        argv.append(f"--gtest_output=xml:{gtest_output_xml}")
    return argv


def render_command_line(argv: Sequence[str], *, is_windows: bool) -> str:
    """Shell-quoted argv reconstructing to that argv (spec §6.1)."""
    if is_windows:
        return subprocess.list2cmdline(list(argv))
    return shlex.join(argv)


def render_exit_code(returncode: int, *, is_windows: bool) -> int:
    """Render the crash/exit code for readability (spec §7.3)."""
    if is_windows:
        return returncode & 0xFFFFFFFF
    if returncode < 0:
        return 128 + (-returncode)
    return returncode


def render_exit_status(returncode: Optional[int], *, timed_out: bool, is_windows: bool) -> str:
    if timed_out:
        return "timeout"
    return str(render_exit_code(returncode, is_windows=is_windows))


def run_binary(argv: Sequence[str], *, timeout: Optional[float]) -> RunOutcome:
    """Run argv, capturing merged stdout+stderr. timeout of 0/None disables enforcement."""
    effective_timeout = timeout if timeout else None
    try:
        completed = subprocess.run(
            list(argv),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=effective_timeout,
        )
        return RunOutcome(
            argv=list(argv),
            output=completed.stdout,
            timed_out=False,
            returncode=completed.returncode,
        )
    except subprocess.TimeoutExpired as exc:
        return RunOutcome(
            argv=list(argv),
            output=exc.output or b"",
            timed_out=True,
            returncode=None,
        )


def execute_and_record(
    binary: Path,
    *,
    output_path: Path,
    command_line_path: Path,
    exit_status_path: Path,
    gtest_output_xml: Optional[Path] = None,
    gtest_filter: Optional[str] = None,
    gtest_list_tests: bool = False,
    timeout: Optional[float],
    is_windows: Optional[bool] = None,
) -> RunOutcome:
    """Prepare the result folder, run once, and record output/command_line/exit_status
    unconditionally (spec §5)."""
    if is_windows is None:
        is_windows = os.name == "nt"

    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    argv = build_argv(
        binary,
        gtest_filter=gtest_filter,
        gtest_output_xml=gtest_output_xml,
        gtest_list_tests=gtest_list_tests,
    )
    outcome = run_binary(argv, timeout=timeout)

    output_path.write_bytes(outcome.output)
    Path(command_line_path).write_text(render_command_line(argv, is_windows=is_windows))
    Path(exit_status_path).write_text(
        render_exit_status(outcome.returncode, timed_out=outcome.timed_out, is_windows=is_windows)
    )
    return outcome
