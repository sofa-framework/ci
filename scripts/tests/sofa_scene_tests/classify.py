"""Output classification: scan stdout/stderr and categorize (spec §6, §6.1)."""

import re
from dataclasses import dataclass

# Crash-signature patterns per §6 — compiled once, immutable.
_CRASH_PATTERNS = (
    re.compile(r"Segmentation fault", re.IGNORECASE),
    re.compile(r"Aborted \(core dumped\)", re.IGNORECASE),
    re.compile(r"terminate called", re.IGNORECASE),
    re.compile(r"Assertion .* failed", re.IGNORECASE),
    re.compile(r"Access violation", re.IGNORECASE),
    re.compile(r"Stack overflow", re.IGNORECASE),
    re.compile(r"Unhandled exception", re.IGNORECASE),
    re.compile(r"Traceback \(most recent call last\)", re.IGNORECASE),
)


@dataclass(frozen=True)
class RunResult:
    stdout: str
    stderr: str
    exit_code: int
    timed_out: bool


@dataclass(frozen=True)
class Classification:
    error_lines: tuple[str, ...]    # lines that triggered error category
    warning_lines: tuple[str, ...]  # lines that triggered warning category
    crash_lines: tuple[str, ...]    # lines/reasons that triggered crash category
    passed: bool

    @property
    def is_error(self) -> bool:
        return bool(self.error_lines)

    @property
    def is_warning(self) -> bool:
        return bool(self.warning_lines)

    @property
    def is_crash(self) -> bool:
        return bool(self.crash_lines)


def _lstripped(line: str) -> str:
    return line.lstrip()


def _is_error_tag(line: str) -> bool:
    return _lstripped(line).startswith("[ERROR]")


def _is_warning_tag(line: str) -> bool:
    return _lstripped(line).startswith("[WARNING]")


def _is_info_tag(line: str) -> bool:
    return _lstripped(line).startswith("[INFO]")


def _scan_for_crash_signature(line: str) -> bool:
    return any(p.search(line) for p in _CRASH_PATTERNS)


def classify(result: RunResult) -> Classification:
    """Classify a RunResult into error / warning / crash categories (§6)."""
    error_lines: list[str] = []
    warning_lines: list[str] = []
    crash_lines: list[str] = []

    # Scan stdout
    for line in result.stdout.splitlines():
        if _is_error_tag(line):
            error_lines.append(line)
        elif _is_warning_tag(line):
            warning_lines.append(line)
        if _scan_for_crash_signature(line):
            crash_lines.append(line)

    # Scan stderr — non-empty non-INFO non-WARNING lines are errors (§6)
    for line in result.stderr.splitlines():
        if not line.strip():
            continue
        if _is_info_tag(line) or _is_warning_tag(line):
            if _is_warning_tag(line):
                warning_lines.append(line)
            if _scan_for_crash_signature(line):
                crash_lines.append(line)
            continue
        # Non-empty, not INFO, not WARNING → error
        error_lines.append(line)
        if _scan_for_crash_signature(line):
            crash_lines.append(line)

    # Non-zero exit code → crash
    if result.exit_code != 0:
        crash_lines.append(f"[exit code: {result.exit_code}]")

    # Timeout → crash
    if result.timed_out:
        crash_lines.append("[killed: timeout]")

    passed = not error_lines and not crash_lines

    return Classification(
        error_lines=tuple(error_lines),
        warning_lines=tuple(warning_lines),
        crash_lines=tuple(crash_lines),
        passed=passed,
    )
