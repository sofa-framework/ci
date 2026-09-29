"""Log-tree mapping helpers (spec §7.1, §8.2, §9.1)."""

from pathlib import Path, PurePath


def compute_bucket_info(
    scene_path: Path, src_dir: Path, build_dir: Path
) -> tuple[str, Path]:
    """Return (bucket_name, bucket_subpath) for an absolute scene_path.

    Raises ValueError if scene_path is outside all known discovery roots.
    """
    try:
        return "src_examples", scene_path.relative_to(src_dir / "examples")
    except ValueError:
        pass

    try:
        return "src_plugins", scene_path.relative_to(
            src_dir / "applications" / "plugins"
        )
    except ValueError:
        pass

    try:
        return "fetched", scene_path.relative_to(
            build_dir / "external_directories" / "fetched"
        )
    except ValueError:
        pass

    raise ValueError(
        f"Scene {scene_path!r} is outside all known discovery roots "
        f"(src_dir={src_dir!r}, build_dir={build_dir!r})"
    )


def scene_log_path(
    test_results_dir: Path, bucket: str, bucket_subpath: Path
) -> Path:
    """Return the absolute path for the scene's .log file under test_results_dir.

    Per §7.1: <test_results_dir>/logs/<bucket>/<bucket_subpath>.log
    The extension is *appended* (bar.scn → bar.scn.log), not replaced.
    """
    return (
        test_results_dir
        / "logs"
        / bucket
        / bucket_subpath.parent
        / (bucket_subpath.name + ".log")
    )


def posix_str(p: PurePath) -> str:
    """Return p as a forward-slash string regardless of host OS (§9.1)."""
    return p.as_posix()
