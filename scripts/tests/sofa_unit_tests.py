#!/usr/bin/env python3
"""Run the SOFA unit-test runner straight from a clone, no `pip install` needed:

    python3 /path/to/SOFA.UnitTests/main.py --build-dir <path> --results-dir <path>

Equivalent to `python -m sofa_unit_tests` / the installed `sofa-unit-tests`
console script — this is just an alternate, no-install entry point.
"""
import sys

from sofa_unit_tests.__main__ import main

if __name__ == "__main__":
    sys.exit(main())
