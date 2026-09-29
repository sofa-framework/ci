"""Scene discovery: walk search roots, parse manifests, build ScenePlans (spec §3, §8.1, §8.2)."""

import ast
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

from .plugins import extract_plugins_python, extract_plugins_xml

_SCENE_EXTENSIONS = frozenset({".scn", ".py", ".pyscn"})
_PYTHON_EXTENSIONS = frozenset({".py", ".pyscn"})

# Parses a valid directive line (directive + 1 or 2 quoted args + optional comment)
_DIRECTIVE_RE = re.compile(
    r"""^\s*(iterations|timeout|ignore|add)\s+"""
    r"""(['"])([^'"]+)\2"""
    r"""(?:\s+(['"])([^'"]+)\4)?"""
    r"""\s*(?:#.*)?$"""
)


# ---------------------------------------------------------------------------
# SceneOverride (§3.5.5 reference shape)
# ---------------------------------------------------------------------------


@dataclass
class SceneOverride:
    iterations: int | None = None
    timeout_sec: int | None = None
    ignored: bool = False


@dataclass
class ManifestRule:
    """One manifest path pattern and the overrides its directives set (§3.5.1).

    `pattern` is the raw text between the quotes; `regex` is that text compiled
    per `compile_manifest_pattern`.
    """

    pattern: str
    regex: re.Pattern
    override: SceneOverride = field(default_factory=SceneOverride)


def compile_manifest_pattern(pattern: str) -> re.Pattern | None:
    """Compile a manifest path pattern into a regex (§3.5.1).

    A manifest path is a regular expression matched in full against the scene's
    path relative to the manifest directory, in POSIX form. A plain path such as
    `Kinect.scn` is therefore its own pattern, while `additional-examples/.*`
    covers a whole subtree.

    One normalization: a pattern ending in `/*` is read as `/.*`. Existing SOFA
    manifests use both spellings for "everything under this directory"
    (`meshing/*`, `jax/*` alongside `python/.*`), and under regex rules the
    glob spelling would otherwise match only the bare directory name.

    @param pattern Raw pattern text from the manifest.
    @return The compiled regex, or None if the pattern is not a valid regex.
    """
    normalized = pattern[:-1] + ".*" if pattern.endswith("/*") else pattern
    try:
        return re.compile(normalized)
    except re.error:
        return None


def override_for(rules: list[ManifestRule], relative_posix: str) -> SceneOverride | None:
    """Merge every manifest rule matching one scene, in manifest order.

    Later directives win for `iterations` and `timeout`; `ignore` is sticky once
    any matching rule sets it.

    @param rules Rules parsed from the manifest governing this scene.
    @param relative_posix Scene path relative to the manifest directory, POSIX form.
    @return The merged override, or None when no rule matched.
    """
    merged: SceneOverride | None = None
    for rule in rules:
        if not rule.regex.fullmatch(relative_posix):
            continue
        if merged is None:
            merged = SceneOverride()
        if rule.override.iterations is not None:
            merged.iterations = rule.override.iterations
        if rule.override.timeout_sec is not None:
            merged.timeout_sec = rule.override.timeout_sec
        if rule.override.ignored:
            merged.ignored = True
    return merged


# ---------------------------------------------------------------------------
# ScenePlan (§8.1)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ScenePlan:
    path: Path
    bucket: str
    bucket_subpath: Path
    test_id: str
    timesteps: int
    timeout_sec: int
    is_python: bool
    required_plugins: tuple[str, ...]
    ignored: bool = False
    ignore_reason: str = ""
    added_via_manifest: Path | None = None
    add_target_missing: bool = False


# ---------------------------------------------------------------------------
# Python scene validation (§3.4)
# ---------------------------------------------------------------------------


def _has_create_scene(scene_path: Path) -> bool:
    """Return True iff file has a top-level createScene function with >=1 arg."""
    source = scene_path.read_text(encoding="utf-8", errors="replace")
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return False
    for node in ast.iter_child_nodes(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if node.name == "createScene" and len(node.args.args) >= 1:
                return True
    return False


# ---------------------------------------------------------------------------
# Fetched eligibility (§3.2)
# ---------------------------------------------------------------------------


def _is_eligible_fetched(name: str) -> bool:
    """Return True iff a fetched subfolder name satisfies §3.2."""
    lower = name.lower()
    if "sofa" not in lower:
        return False
    if lower.endswith("-temp") or lower.endswith("-build"):
        return False
    return True


# ---------------------------------------------------------------------------
# Manifest parser (§3.5)
# ---------------------------------------------------------------------------


def parse_scene_tests(
    manifest_path: Path,
) -> tuple[list[ManifestRule], list[Path]]:
    """Parse a .scene-tests manifest (§3.5).

    Returns (rules_in_file_order, added_scene_paths).  Each rule carries the
    pattern its directives were written against; `override_for` applies them to
    a scene.  `add` is the exception — it names one file to inject, not a
    pattern, so its argument is resolved to an absolute path here.

    Never raises — malformed lines emit a warning and are skipped (§3.5.6); so
    does a pattern that is not a valid regular expression.
    """
    rules: dict[str, ManifestRule] = {}
    added: list[Path] = []
    manifest_dir = manifest_path.parent

    def rule_for(pattern: str, lineno: int, raw: str) -> ManifestRule | None:
        """Return the rule for this pattern, creating and compiling it once."""
        existing = rules.get(pattern)
        if existing is not None:
            return existing
        regex = compile_manifest_pattern(pattern)
        if regex is None:
            print(
                f"Warning: malformed line in {manifest_path}:{lineno}: {raw.rstrip()}",
                file=sys.stderr,
            )
            return None
        rule = ManifestRule(pattern=pattern, regex=regex)
        rules[pattern] = rule
        return rule

    lines = manifest_path.read_text(encoding="utf-8", errors="replace").splitlines()
    for lineno, raw_line in enumerate(lines, 1):
        # Strip inline comment then check for blank
        line = raw_line.split("#")[0].rstrip()
        if not line.strip():
            continue

        m = _DIRECTIVE_RE.match(line)
        if not m:
            print(
                f"Warning: malformed line in {manifest_path}:{lineno}: {raw_line.rstrip()}",
                file=sys.stderr,
            )
            continue

        directive = m.group(1)
        pattern = m.group(3)
        value = m.group(5)  # None if second arg not present

        if directive == "add":
            added.append((manifest_dir / Path(pattern)).resolve())
            continue

        if directive in ("iterations", "timeout"):
            if value is None:
                print(
                    f"Warning: malformed line in {manifest_path}:{lineno}: {raw_line.rstrip()}",
                    file=sys.stderr,
                )
                continue
            try:
                n = int(value)
            except ValueError:
                print(
                    f"Warning: malformed line in {manifest_path}:{lineno}: {raw_line.rstrip()}",
                    file=sys.stderr,
                )
                continue
            rule = rule_for(pattern, lineno, raw_line)
            if rule is None:
                continue
            if directive == "iterations":
                rule.override.iterations = n
            else:
                rule.override.timeout_sec = n

        elif directive == "ignore":
            rule = rule_for(pattern, lineno, raw_line)
            if rule is None:
                continue
            rule.override.ignored = True

    return list(rules.values()), added


# ---------------------------------------------------------------------------
# ScenePlan construction helpers
# ---------------------------------------------------------------------------


def _make_test_id(bucket: str, bucket_subpath: Path) -> str:
    return f"{bucket}::{bucket_subpath.as_posix()}"


def _build_plan(
    scene_path: Path,
    bucket: str,
    bucket_base: Path,
    config,
    ov: SceneOverride | None,
    manifest_path: Path | None,
) -> ScenePlan:
    bucket_subpath = scene_path.relative_to(bucket_base)
    test_id = _make_test_id(bucket, bucket_subpath)

    timesteps = ov.iterations if (ov and ov.iterations is not None) else config.timesteps
    timeout_sec = ov.timeout_sec if (ov and ov.timeout_sec is not None) else config.timeout_sec
    ignored = ov.ignored if ov else False
    ignore_reason = (
        f"ignored by .scene-tests at {manifest_path}" if (ignored and manifest_path) else ""
    )

    is_python = scene_path.suffix.lower() in _PYTHON_EXTENSIONS
    if is_python:
        required_plugins = tuple(extract_plugins_python(scene_path))
    else:
        required_plugins = tuple(extract_plugins_xml(scene_path))

    return ScenePlan(
        path=scene_path,
        bucket=bucket,
        bucket_subpath=bucket_subpath,
        test_id=test_id,
        timesteps=timesteps,
        timeout_sec=timeout_sec,
        is_python=is_python,
        required_plugins=required_plugins,
        ignored=ignored,
        ignore_reason=ignore_reason,
        added_via_manifest=None,
        add_target_missing=False,
    )


def _build_added_plan(
    added_path: Path,
    bucket: str,
    bucket_base: Path,
    config,
    ov: SceneOverride | None,
    manifest_path: Path,
) -> ScenePlan:
    add_target_missing = not added_path.is_file()

    try:
        bucket_subpath = added_path.relative_to(bucket_base)
    except ValueError:
        bucket_subpath = Path(added_path.name)

    test_id = _make_test_id(bucket, bucket_subpath)

    timesteps = ov.iterations if (ov and ov.iterations is not None) else config.timesteps
    timeout_sec = ov.timeout_sec if (ov and ov.timeout_sec is not None) else config.timeout_sec
    ignored = ov.ignored if ov else False
    ignore_reason = (
        f"ignored by .scene-tests at {manifest_path}" if ignored else ""
    )

    is_python = added_path.suffix.lower() in _PYTHON_EXTENSIONS

    if add_target_missing:
        required_plugins: tuple[str, ...] = ()
    elif is_python:
        required_plugins = tuple(extract_plugins_python(added_path))
    else:
        required_plugins = tuple(extract_plugins_xml(added_path))

    return ScenePlan(
        path=added_path,
        bucket=bucket,
        bucket_subpath=bucket_subpath,
        test_id=test_id,
        timesteps=timesteps,
        timeout_sec=timeout_sec,
        is_python=is_python,
        required_plugins=required_plugins,
        ignored=ignored,
        ignore_reason=ignore_reason,
        added_via_manifest=manifest_path,
        add_target_missing=add_target_missing,
    )


# ---------------------------------------------------------------------------
# Leaf-folder processor
# ---------------------------------------------------------------------------


def _process_leaf(
    leaf_dir: Path,
    bucket: str,
    bucket_base: Path,
    config,
    plans: list[ScenePlan],
) -> None:
    """Walk a single examples/ or scenes/ directory and collect ScenePlans."""
    if not leaf_dir.is_dir():
        return

    # Discover and parse the manifest at this leaf root only (§3.5)
    manifest_file = leaf_dir / ".scene-tests"
    rules: list[ManifestRule] = []
    added_paths: list[Path] = []
    if manifest_file.is_file():
        rules, added_paths = parse_scene_tests(manifest_file)
        active_manifest: Path | None = manifest_file
    else:
        active_manifest = None

    # Manifest patterns are matched against the path relative to the manifest
    # directory (§3.5.1).  `add` resolves its argument, so match those against
    # the resolved leaf directory.
    leaf_resolved = leaf_dir.resolve()

    def relative_posix(scene_path: Path) -> str:
        for base in (leaf_dir, leaf_resolved):
            try:
                return scene_path.relative_to(base).as_posix()
            except ValueError:
                continue
        return scene_path.name

    # Walk for candidate scenes
    for scene_path in sorted(leaf_dir.rglob("*")):
        if not scene_path.is_file():
            continue
        if scene_path.suffix.lower() not in _SCENE_EXTENSIONS:
            continue
        is_python = scene_path.suffix.lower() in _PYTHON_EXTENSIONS
        if is_python and not _has_create_scene(scene_path):
            continue
        ov = override_for(rules, relative_posix(scene_path))
        plans.append(
            _build_plan(scene_path, bucket, bucket_base, config, ov, active_manifest)
        )

    # Inject scenes from `add` directives
    for added_abs in added_paths:
        ov = override_for(rules, relative_posix(added_abs))
        plans.append(
            _build_added_plan(added_abs, bucket, bucket_base, config, ov, manifest_file)
        )


# ---------------------------------------------------------------------------
# Main discovery entry point
# ---------------------------------------------------------------------------


def discover_scenes(config) -> list[ScenePlan]:
    """Walk all §3.1 search roots and return a list of ScenePlan instances."""
    plans: list[ScenePlan] = []

    src = config.src_dir
    build = config.build_dir

    # Bucket 1: SRC_DIR/examples/**
    _process_leaf(
        src / "examples",
        bucket="src_examples",
        bucket_base=src / "examples",
        config=config,
        plans=plans,
    )

    # Buckets 2 & 3: SRC_DIR/applications/plugins/*/examples/** and scenes/**
    plugins_root = src / "applications" / "plugins"
    if plugins_root.is_dir():
        for plugin_dir in sorted(plugins_root.iterdir()):
            if not plugin_dir.is_dir():
                continue
            for sub in ("examples", "scenes"):
                _process_leaf(
                    plugin_dir / sub,
                    bucket="src_plugins",
                    bucket_base=plugins_root,
                    config=config,
                    plans=plans,
                )

    # Buckets 4 & 5: BUILD_DIR/external_directories/fetched/<eligible>/examples/** and scenes/**
    fetched_root = build / "external_directories" / "fetched"
    if fetched_root.is_dir():
        for fetched_dir in sorted(fetched_root.iterdir()):
            if not fetched_dir.is_dir():
                continue
            if not _is_eligible_fetched(fetched_dir.name):
                continue
            for sub in ("examples", "scenes"):
                _process_leaf(
                    fetched_dir / sub,
                    bucket="fetched",
                    bucket_base=fetched_root,
                    config=config,
                    plans=plans,
                )

    return plans
