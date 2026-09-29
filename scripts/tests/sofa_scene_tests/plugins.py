"""Plugin availability check: extract RequiredPlugin names and verify binaries (spec §4)."""

import ast
import fnmatch
import itertools
import re
import sys
from pathlib import Path
from typing import Mapping

_PREFIXES = ("", "lib")
_DEBUG_SUFFIXES = ("", "d", "_d")
_EXTENSIONS = (".dylib", ".so", ".lib", ".dll")


def normalize_plugin_value(raw: str | list[str]) -> list[str]:
    """Normalize a RequiredPlugin value (string or list) into a list of plugin names.

    Per §4.1.1 — handles bare string, whitespace/comma-separated, bracketed
    list literals, and Python list[str] values from the AST.
    """
    if isinstance(raw, list):
        return [s.strip() for s in raw if s and s.strip()]
    s = raw.strip()
    if s.startswith("[") and s.endswith("]"):
        s = s[1:-1]
    parts = s.split(",") if "," in s else s.split()
    return [p.strip().strip("'\"") for p in parts if p.strip().strip("'\"")]


def extract_plugins_xml(scene_path: Path) -> list[str]:
    """Extract plugin names from a .scn (XML) scene file (§4.1.2)."""
    results: list[str] = []
    content = scene_path.read_text(encoding="utf-8", errors="replace")
    for line in content.splitlines():
        stripped = line.lstrip()
        if not stripped.startswith("<"):
            continue
        after_lt = stripped[1:].lstrip()
        if not after_lt.startswith("RequiredPlugin"):
            continue
        # Try pluginName first, then name (per §4.1.2)
        match = re.search(r'pluginName=["\']([^"\']*)["\']', line)
        if not match:
            match = re.search(r'\bname=["\']([^"\']*)["\']', line)
        if not match:
            print(
                f"Warning: unknown RequiredPlugin found in {scene_path}",
                file=sys.stderr,
            )
            continue
        results.extend(normalize_plugin_value(match.group(1)))
    return results


def extract_plugins_python(scene_path: Path) -> list[str]:
    """Extract plugin names from a .py/.pyscn scene using AST walking (§4.1.3)."""
    results: list[str] = []
    source = scene_path.read_text(encoding="utf-8", errors="replace")
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return []

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if not isinstance(func, ast.Attribute) or func.attr != "addObject":
            continue
        if not node.args:
            continue
        first = node.args[0]
        if not (isinstance(first, ast.Constant) and first.value == "RequiredPlugin"):
            continue

        # Search keywords: pluginName first, then name
        plugin_kw = None
        for kw in node.keywords:
            if kw.arg == "pluginName":
                plugin_kw = kw
                break
        if plugin_kw is None:
            for kw in node.keywords:
                if kw.arg == "name":
                    plugin_kw = kw
                    break
        if plugin_kw is None:
            continue

        val = plugin_kw.value
        if isinstance(val, ast.Constant) and isinstance(val.value, str):
            results.extend(normalize_plugin_value(val.value))
        elif isinstance(val, (ast.List, ast.Tuple)):
            names: list[str] = []
            dynamic = False
            for elt in val.elts:
                if isinstance(elt, ast.Constant) and isinstance(elt.value, str):
                    names.append(elt.value)
                else:
                    dynamic = True
                    break
            if dynamic:
                print(
                    f"Warning: dynamic RequiredPlugin in {scene_path}:{node.lineno}",
                    file=sys.stderr,
                )
            else:
                results.extend(normalize_plugin_value(names))
        else:
            print(
                f"Warning: dynamic RequiredPlugin in {scene_path}:{node.lineno}",
                file=sys.stderr,
            )
    return results


def _build_plugin_patterns(plugin_name: str) -> list[str]:
    """Build the 24 fnmatch patterns for a plugin name (§4.2, §4.2.3)."""
    return [
        f"{prefix}{plugin_name}{suffix}{ext}*"
        for prefix, suffix, ext in itertools.product(
            _PREFIXES, _DEBUG_SUFFIXES, _EXTENSIONS
        )
    ]


def _candidate_dirs(build_dir: Path, environ: Mapping[str, str]) -> list[Path]:
    """Return candidate directories in the order specified by §4.2.2."""
    dirs: list[Path] = [build_dir / "lib"]
    if sys.platform == "win32":
        dirs.append(build_dir / "bin")
    plugin_path_str = environ.get("SOFA_PLUGIN_PATH", "")
    if plugin_path_str:
        sep = ";" if sys.platform == "win32" else ":"
        for entry in plugin_path_str.split(sep):
            p = Path(entry)
            if p.is_dir():
                dirs.append(p)
    return dirs


def plugin_is_available(
    plugin_name: str, build_dir: Path, environ: Mapping[str, str]
) -> bool:
    """Return True if a binary matching plugin_name exists in any candidate dir (§4.2)."""
    patterns = [p.lower() for p in _build_plugin_patterns(plugin_name)]
    for candidate_dir in _candidate_dirs(build_dir, environ):
        try:
            for entry in candidate_dir.iterdir():
                name_lower = entry.name.lower()
                if any(fnmatch.fnmatchcase(name_lower, pat) for pat in patterns):
                    return True
        except OSError:
            pass
    return False


def check_plugins(
    required: list[str], build_dir: Path, environ: Mapping[str, str]
) -> list[str]:
    """Return names of required plugins not found in any candidate directory."""
    return [p for p in required if not plugin_is_available(p, build_dir, environ)]


def missing_plugin_skip_reason(missing: list[str]) -> str:
    """Return a human-readable skip reason naming the missing plugins (§4.3)."""
    names = ", ".join(missing)
    return f"Required plugin(s) not found in build tree: {names}"
