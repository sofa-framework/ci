"""XML-first pass/fail classification of a GoogleTest report.xml (spec §7)."""
from __future__ import annotations

import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional

_FAILURE_TAGS = ("failure", "error")


@dataclass(frozen=True)
class TestCaseResult:
    suite: str
    name: str
    failure_texts: List[str] = field(default_factory=list)

    @property
    def failed(self) -> bool:
        return bool(self.failure_texts)


@dataclass(frozen=True)
class ParsedReport:
    tests: int
    disabled: int
    failures: int
    errors: int
    testcases: List[TestCaseResult]

    @property
    def passed(self) -> bool:
        return not any(tc.failed for tc in self.testcases)


def _int_attr(elem: ET.Element, name: str) -> int:
    try:
        return int(elem.get(name, 0))
    except (TypeError, ValueError):
        return 0


def parse_report(path: Path) -> Optional[ParsedReport]:
    """Parse a GoogleTest report.xml; None if missing or not well-formed (spec §7)."""
    path = Path(path)
    if not path.is_file():
        return None

    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return None

    testcases = []
    for elem in root.iter("testcase"):
        failure_texts = [
            (child.text or "") for child in elem if child.tag in _FAILURE_TAGS
        ]
        testcases.append(
            TestCaseResult(
                suite=elem.get("classname", ""),
                name=elem.get("name", ""),
                failure_texts=failure_texts,
            )
        )

    return ParsedReport(
        tests=_int_attr(root, "tests"),
        disabled=_int_attr(root, "disabled"),
        failures=_int_attr(root, "failures"),
        errors=_int_attr(root, "errors"),
        testcases=testcases,
    )
