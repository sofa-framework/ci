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


# SOFA's own message severities (Sofa::helper::logging::Message::Type), and the
# literal tag text MessageFormatter.cpp prefixes each one with. Only Error/Fatal
# are real failures; Info/Advice/Deprecated/Warning are routine, expected noise
# (e.g. the ubiquitous "name= instead of pluginName=" RequiredPlugin notice, or
# a SceneChecking suggestion) that SOFA itself does not consider an error.
_BENIGN_TAGS = ("[INFO]", "[DEPRECATED]", "[SUGGESTION]")  # Info, Deprecated, Advice
_WARNING_TAGS = ("[WARNING]",)
_ERROR_TAGS = ("[ERROR]", "[FATAL]")

# The Python interpreter's own `warnings` module (not SOFA's) emits a two-line
# block in this exact shape, e.g.:
#   /usr/lib/python3/dist-packages/pyparsing/core.py:5640: SyntaxWarning: 'return' in a 'finally' block
#     return self.__class__.__name__ + ": " + retString
# It has no SOFA "[TAG]" and is printed to stderr (stderr's default category
# is "error" — see `classify`), so without recognizing it explicitly it reads
# as an unprompted stderr error. It's routine Python-version noise (e.g. a new
# SyntaxWarning a dependency only triggers under a newer Python, such as 3.14)
# unrelated to SOFA or the scene under test, so treat it like SOFA's own
# [WARNING] tag: opens a "warning" category block, whose untagged continuation
# line(s) inherit it via the normal `_scan_stream` mechanism.
_PY_WARNING_RE = re.compile(r"^\S+:\d+:\s*\w+Warning:\s")


def _tag_category(line: str):
    """Return "warning"/"benign"/"error" if `line` opens a tagged SOFA message
    or a Python interpreter warning, else None (an untagged line, which is
    either free-form output or the continuation of a preceding multi-line
    message — see `_scan_stream`)."""
    stripped = _lstripped(line)
    if stripped.startswith(_WARNING_TAGS):
        return "warning"
    if stripped.startswith(_BENIGN_TAGS):
        return "benign"
    if stripped.startswith(_ERROR_TAGS):
        return "error"
    if _PY_WARNING_RE.match(stripped):
        return "warning"
    return None


def _scan_for_crash_signature(line: str) -> bool:
    return any(p.search(line) for p in _CRASH_PATTERNS)


def _scan_stream(lines, *, default_category: str):
    """Classify every non-blank line of one stream (§6).

    SOFA's msg_* helpers only prefix the *first* physical line of a (possibly
    multi-line) message with its "[TAG]" — continuation lines are printed raw.
    So an untagged line inherits the category of the most recently seen tag in
    this stream, rather than being judged on its own; `default_category` is
    what an untagged line counts as before any tag has been seen at all
    (stdout gives the benefit of the doubt; stderr does not — see `classify`).
    """
    error_lines: list[str] = []
    warning_lines: list[str] = []
    crash_lines: list[str] = []

    current_category = default_category
    for line in lines:
        if not line.strip():
            continue
        tag = _tag_category(line)
        if tag is not None:
            current_category = tag

        if current_category == "error":
            error_lines.append(line)
        elif current_category == "warning":
            warning_lines.append(line)

        if _scan_for_crash_signature(line):
            crash_lines.append(line)

    return error_lines, warning_lines, crash_lines


def classify(result: RunResult) -> Classification:
    """Classify a RunResult into error / warning / crash categories (§6)."""
    # stdout: an untagged line before any tag is seen is benign (§6).
    out_errors, out_warnings, out_crashes = _scan_stream(
        result.stdout.splitlines(), default_category="benign"
    )
    # stderr: an untagged line before any tag is seen is treated as an error —
    # unlike stdout, nothing routine is expected to show up here unprompted.
    err_errors, err_warnings, err_crashes = _scan_stream(
        result.stderr.splitlines(), default_category="error"
    )

    error_lines = out_errors + err_errors
    warning_lines = out_warnings + err_warnings
    crash_lines = out_crashes + err_crashes

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
