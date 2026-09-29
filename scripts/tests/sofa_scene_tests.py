"""Standalone launcher — run the scene tests from any working directory.

    python3 /path/to/SOFA.SceneTests/sofa_scene_tests.py \
        --src-dir /path/to/sofa \
        --build-dir /path/to/sofa/.pixi/envs/supported-plugins-dev/sofa-build \
        --test-results-dir /path/to/scene-tests-results

Equivalent to `python -m sofa_scene_tests` run from the repo root, but it does
not require the repo to be the working directory or to be on PYTHONPATH: the
script puts its own directory on sys.path first. All arguments are forwarded
untouched, and the exit code is passed through (0 = no failures, 1 = at least
one failure or an empty selection). See `--help` for the full option list.

Pass it to `python3` explicitly, as above; the file is not marked executable
and carries no shebang. A symlink to it works — `__file__` is resolved through
symlinks before the repo root is derived from it.

Note on the name: this module sits next to the `sofa_scene_tests/` package
directory. That is deliberate and safe — Python resolves a package directory
ahead of a same-named module file, so `import sofa_scene_tests` below (and
`python -m sofa_scene_tests`) always finds the package, never this script.
"""

import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from sofa_scene_tests.__main__ import main  # noqa: E402  (needs sys.path above)

if __name__ == "__main__":
    sys.exit(main())
