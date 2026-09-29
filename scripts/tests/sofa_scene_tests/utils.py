"""Console helpers shared with SOFA.UnitTests (`sofa_unit_tests/utils.py`).

Kept deliberately close to its counterpart there so both tools print the same
way: a colored "[STATUS]" prefix per test, emitted as one block per test so
concurrent workers never interleave half-lines.
"""

import os
from dataclasses import dataclass

from .classify import Classification, RunResult
from .discovery import ScenePlan
import enum


class Logs:
    GREEN = "\033[92m"
    RED = "\033[91m"
    YELLOW = "\033[93m"
    CYAN = "\033[96m"
    RESET = "\033[0m"

    COLORS = {
        "PASSED": GREEN,
        "FAILED": RED,
        "CRASHED": YELLOW,
        "SKIPPED": CYAN,
    }

    def __init__(self):
        """Build the logger and make sure ANSI escape codes are honoured by the terminal."""
        # Enable ANSI colors in Windows cmd/PowerShell (Windows 10+)
        if os.name == "nt":
            os.system("")

    def msg_any(self, msg_type, message):
        """Format a message with a colored "[TYPE]" prefix.

        @param msg_type Status label, e.g. "PASSED"; unknown labels get no color.
        @param message Text appended after the prefix, kept in the default color.
        @return The formatted, ANSI-colored string.
        """
        # Known types get their color; unknown types fall back to default
        color = self.COLORS.get(msg_type, self.RESET)
        # Only the prefix is colored; the message keeps the default color
        return f"{color}[{msg_type}] {self.RESET}{message}"

    def msg_passed(self, message):
        """Format a message as a success line.

        @param message Text to display after the prefix.
        @return The message prefixed with a green "[PASSED]".
        """
        return self.msg_any("PASSED", message)

    def msg_failed(self, message):
        """Format a message as a failure line.

        @param message Text to display after the prefix.
        @return The message prefixed with a red "[FAILED]".
        """
        return self.msg_any("FAILED", message)

    def msg_crashed(self, message):
        """Format a message as a crash line.

        @param message Text to display after the prefix.
        @return The message prefixed with a yellow "[CRASHED]".
        """
        return self.msg_any("CRASHED", message)

    def msg_skipped(self, message):
        """Format a message as a skip line.

        @param message Text to display after the prefix.
        @return The message prefixed with a cyan "[SKIPPED]".
        """
        return self.msg_any("SKIPPED", message)


class SubList(object):
    def __init__(self, origList, beginIdx, endIdx):
        """Create a re-iterable view over the [beginIdx, endIdx) slice of a list.

        The underlying list is referenced, not copied, so later changes to it are visible.

        @param origList List to expose a window of.
        @param beginIdx Index of the first element of the window.
        @param endIdx Index just past the last element of the window.
        @throw IndexError If either bound falls outside the list.
        """
        self.origList = origList
        self.beginIdx = beginIdx
        self.endIdx = endIdx

        self.restartContainer()

        if(endIdx > len(origList) or endIdx < 0):
            raise IndexError("endIdx must be taken be between 0 and the length of the list")

        if(beginIdx > len(origList) - 1 or beginIdx < 0):
            raise IndexError("beginIdx must be taken be between 0 and the length of the list-1")

    def restartContainer(self):
        """Rewind the internal cursor so the window can be iterated over again."""
        self.currId=self.beginIdx

    def __iter__(self):
        """Expose the view itself as its own iterator.

        @return This SubList instance.
        """
        return self

    def __next__(self):
        """Return the next element of the window, rewinding once its end is reached.

        @return The next element of the underlying list.
        @throw StopIteration When the end of the window is reached.
        """

        if(self.currId == self.endIdx):
            self.restartContainer()
            raise StopIteration  # Done iterating
        self.currId += 1
        return self.origList[self.currId-1]


# ---------------------------------------------------------------------------
# Single-scene test driver (§3.5.2, §4.3, §6.1, §7)
# ---------------------------------------------------------------------------


class SceneStatus(enum.Enum):
    """Outcome of one scene test."""

    PASSED = "passed"
    FAILED = "failed"
    CRASHED = "crashed"
    SKIPPED = "skipped"


@dataclass(frozen=True)
class SceneOutcome:
    """The result of running one scene test end-to-end.

    `message` carries the skip reason for SKIPPED and the failure details for
    FAILED; it is empty for PASSED.  `result` and `classification` are None for
    outcomes decided before runSofa was launched (ignored, missing add target,
    missing plugin).
    """

    plan: ScenePlan
    status: SceneStatus
    message: str = ""
    result: RunResult | None = None
    classification: Classification | None = None

    @property
    def passed(self) -> bool:
        return self.status is SceneStatus.PASSED

    @property
    def failed(self) -> bool:
        return self.status is SceneStatus.FAILED

    @property
    def crashed(self) -> bool:
        return self.status is SceneStatus.CRASHED

    @property
    def skipped(self) -> bool:
        return self.status is SceneStatus.SKIPPED
