"""Result-tree path layout for the SOFA unit-test runner (spec §6)."""
from __future__ import annotations

from pathlib import Path

_ILLEGAL_CHARS = '/\\:*?"<>|'


def sanitize_component(name: str) -> str:
    """Replace filesystem-illegal characters with '_' (spec §6.2)."""
    return "".join("_" if c in _ILLEGAL_CHARS else c for c in name)


def summary_txt_path(results_dir: Path) -> Path:
    return Path(results_dir) / "summary.txt"


def failed_tests_path(results_dir: Path) -> Path:
    return Path(results_dir) / "unit_failures.txt"


def crashed_tests_path(results_dir: Path) -> Path:
    return Path(results_dir) / "unit_crashes.txt"


def binary_dir(results_dir: Path, test_name: str) -> Path:
    return Path(results_dir) / test_name


def report_xml_path(directory: Path) -> Path:
    return Path(directory) / "report.xml"


def output_path(directory: Path) -> Path:
    return Path(directory) / "output"


def exit_status_path(directory: Path) -> Path:
    return Path(directory) / "exit_status"


def command_line_path(directory: Path) -> Path:
    return Path(directory) / "command_line"


def subtests_dir(binary_dir_: Path) -> Path:
    return Path(binary_dir_) / "subtests"


def subtest_dir(binary_dir_: Path, suite: str, case: str) -> Path:
    """On-disk folder for one re-run sub-test, name sanitized (spec §6.2)."""
    sanitized = sanitize_component(f"{suite}.{case}")
    return subtests_dir(binary_dir_) / sanitized
