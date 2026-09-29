"""Build env+cmd, launch runSofa, manage timeout and process tree kill (spec §5).

Also hosts the single-scene test driver (`run_scene_test`) and the whole-session
driver (`run_all`): selection, the worker threads draining a shared job pool,
the per-scene console block, the deferred summary writing and the end-of-run
summary.  This mirrors `sofa_unit_tests/runner.py`, so both tools present the
same front end.

The results tree is filled in two steps, and that is what keeps the workers
lock-free.  Each worker writes its own scene's .log as it goes — one file per
scene, disjoint paths, so two workers never meet there — and the shared summary
files at the root are appended to afterwards, single-threaded, by
`write_reports`.  Beyond that the workers share only a job pool, an outcome list
and a counter, each manipulated through operations that are atomic on their own.
"""

import fnmatch
import itertools
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Mapping, Sequence

from .classify import Classification, RunResult, classify
from .discovery import ScenePlan, discover_scenes
from .plugins import check_plugins, missing_plugin_skip_reason
from .reporting import (
    initialize_report_dir,
    record_summary_entries,
    write_scene_log,
    _write_summary_txt
)
from .utils import Logs, SceneOutcome, SceneStatus


def _build_env(config) -> dict[str, str]:
    """Build the subprocess environment dict (§5.1).

    Sets SOFA_ROOT and prepends PYTHONPATH. Never modifies os.environ.
    """
    env = os.environ.copy()
    env["SOFA_ROOT"] = str(config.build_dir)
    sep = ";" if sys.platform == "win32" else ":"
    site_packages = str(config.build_dir / "lib" / "python3" / "site-packages")
    existing_py = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = f"{site_packages}{sep}{existing_py}" if existing_py else site_packages
    return env


def _build_command(config, plan: ScenePlan) -> list[str]:
    """Build the runSofa argv list (§5.2).

    --noautoload prevents default plugin_list.conf.default from loading.
    Several plugins in the default list have destructors that corrupt the heap
    when run without hardware (GPU, haptics) — they SIGABRT on process exit
    even after a successful simulation.  Scenes declare their dependencies via
    <RequiredPlugin>, which runSofa still honours under --noautoload.
    """
    cmd = [str(config.runsofa), "--noautoload", "-g", "batch", "-n", str(plan.timesteps)]
    if plan.is_python:
        cmd += ["-l", "SofaPython3"]
    cmd.append(str(plan.path))
    return cmd


def _kill_tree_posix(pid: int) -> None:
    """SIGTERM the process group, wait 5 s, then SIGKILL if still running (§5.3)."""
    try:
        pgid = os.getpgid(pid)
        os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError:
        return
    time.sleep(5)
    try:
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def _kill_tree_windows(pid: int) -> None:
    """taskkill /F /T /PID to reap the whole Windows process tree (§5.3)."""
    subprocess.run(
        ["taskkill", "/F", "/T", "/PID", str(pid)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def run_scene(config, plan: ScenePlan) -> RunResult:
    """Launch runSofa for a single scene and return a RunResult (§5).

    Never modifies os.environ (§10.5). shell=False always (§11).
    """
    env = _build_env(config)
    cmd = _build_command(config, plan)

    popen_kwargs: dict = {
        "stdout": subprocess.PIPE,
        "stderr": subprocess.PIPE,
        "env": env,
        "shell": False,
        "encoding": "utf-8",
        "errors": "replace",
    }
    if sys.platform == "win32":
        popen_kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        popen_kwargs["start_new_session"] = True

    proc = subprocess.Popen(cmd, **popen_kwargs)
    timed_out = False
    try:
        stdout, stderr = proc.communicate(timeout=plan.timeout_sec)
    except subprocess.TimeoutExpired:
        timed_out = True
        if sys.platform == "win32":
            _kill_tree_windows(proc.pid)
        else:
            _kill_tree_posix(proc.pid)
        stdout, stderr = proc.communicate()

    return RunResult(
        stdout=stdout,
        stderr=stderr,
        exit_code=proc.returncode,
        timed_out=timed_out,
    )




def _failure_details(plan: ScenePlan, classification: Classification) -> str:
    """Render the human-readable failure message for a non-passing scene (§6.1)."""
    details = []
    if classification.error_lines:
        details.append("Errors:\n  " + "\n  ".join(classification.error_lines))
    if classification.crash_lines:
        details.append("Crashes:\n  " + "\n  ".join(classification.crash_lines))
    return "\n".join(details) or f"Scene failed: {plan.path}"


def run_scene_test(
    config,
    plan: ScenePlan,
    environ: Mapping[str, str] | None = None,
) -> SceneOutcome:
    """Run one scene through the full pipeline and decide its outcome.

    Sequence: ignore check (§3.5.2) → missing `add` target (§3.5.2) → plugin
    availability (§4.3) → launch (§5) → classify (§6) → write the .log (§7.1).

    The scene's own .log is written here, so a long run can be inspected while
    it is still going.  That needs no lock: one log per scene, disjoint paths.
    The shared summary files at the root of the results tree are the contended
    part, and those are left to `write_reports` once the run is over (§7.2).
    """
    if environ is None:
        environ = os.environ

    # --- Ignored scenes are skipped, naming the manifest (§3.5.2) ---
    if plan.ignored:
        return SceneOutcome(plan, SceneStatus.SKIPPED, plan.ignore_reason)

    # --- add-injected scene whose file does not exist → failure (§3.5.2) ---
    if plan.add_target_missing:
        write_scene_log(config.test_results_dir, plan, None)
        return SceneOutcome(
            plan, SceneStatus.CRASHED, f"Scene file not found: {plan.path}"
        )

    # --- Plugin availability check (§4.3) ---
    missing = check_plugins(list(plan.required_plugins), config.build_dir, dict(environ))
    if missing:
        return SceneOutcome(
            plan, SceneStatus.SKIPPED, missing_plugin_skip_reason(missing)
        )

    # --- Launch, classify, write the scene's own log (§5, §6, §7.1) ---
    result = run_scene(config, plan)
    classification = classify(result)
    write_scene_log(config.test_results_dir, plan, result)

    if classification.passed:
        return SceneOutcome(
            plan, SceneStatus.PASSED, "", result, classification
        )


    if result.exit_code != 0:
        return SceneOutcome(
            plan, SceneStatus.CRASHED, "", result, classification
        )

    return SceneOutcome(
        plan,
        SceneStatus.FAILED,
        _failure_details(plan, classification),
        result,
        classification,
    )


# ---------------------------------------------------------------------------
# Selection (§3, §2 -k/--exclude)
# ---------------------------------------------------------------------------


def matches_pattern(test_id: str, pattern: str) -> bool:
    """Match one scene ID against one pattern.

    A pattern carrying a glob metacharacter is matched with fnmatch against the
    whole ID; anything else is a plain substring test. This keeps the common
    cases literal (`Demos`, `.py`, `fetched::SofaPython3`, a full ID) while
    still allowing anchored patterns (`src_examples::Component/*`).
    """
    if "*" in pattern or "?" in pattern:
        return fnmatch.fnmatchcase(test_id, pattern)
    return pattern in test_id


def filter_plans(
    plans: Sequence[ScenePlan],
    include: Sequence[str] | None = None,
    exclude: Sequence[str] | None = None,
) -> list[ScenePlan]:
    """Select plans by scene ID: keep any --filter match, then drop any --exclude match.

    Order is preserved. Empty/None include means "keep everything".
    """
    selected = list(plans)
    if include:
        selected = [
            p for p in selected
            if any(matches_pattern(p.test_id, pat) for pat in include)
        ]
    if exclude:
        selected = [
            p for p in selected
            if not any(matches_pattern(p.test_id, pat) for pat in exclude)
        ]
    return selected


def selected_scenes(config) -> tuple[list[ScenePlan], int]:
    """Discover the scenes of the source tree and keep those the user asked for.

    @param config Configuration providing the source tree and the filter/exclude patterns.
    @return The selected plans, in discovery order, and the discovered total.
    """
    discovered = discover_scenes(config)
    return filter_plans(discovered, config.filters, config.excludes), len(discovered)


# ---------------------------------------------------------------------------
# Session driver (§10)
# ---------------------------------------------------------------------------

_STATUS_LABEL = {
    SceneStatus.PASSED: "PASSED",
    SceneStatus.FAILED: "FAILED",
    SceneStatus.SKIPPED: "SKIPPED",
    SceneStatus.CRASHED: "CRASHED",
}


def _raw_output(outcome: SceneOutcome) -> str:
    """Render the raw runSofa output of one scene, for --verbose 2.

    Read from the outcome rather than from the .log just written for it: same
    text, and no reason to go back to the filesystem for it.
    """
    if outcome.result is None:
        return f"(no output captured for {outcome.plan.test_id})"
    return outcome.result.stdout + outcome.result.stderr


def run_scenes(pending, outcomes, executed, total, config) -> None:
    """Drain a shared pool of scenes, running and reporting each one on the fly.

    Meant to be the body of a worker thread: the pool is popped from until
    empty, so several concurrent calls share the same list of jobs.  Each
    scene's console output is assembled in full and printed in one call, so
    concurrent workers never interleave half-lines.

    No lock is taken.  Every shared operation here is atomic in its own right:
    `list.pop` and `list.append` are, and `next()` on an itertools.count is —
    unlike `+= 1`, which is a read-modify-write two workers can race on.  Of the
    results tree, a worker touches only its own scene's .log; the shared summary
    files are left to `write_summaries`.

    @param pending Shared, mutable list of scene plans, consumed from the end.
    @param outcomes Shared list every finished outcome is appended to.
    @param executed Shared counter handing out the 1-based progress index.
    @param total Number of scenes in the session, for the progress line.
    @param config Configuration of the run (results directory, verbosity).
    """
    logs = Logs()

    while True:
        # Popping under try/except rather than after an emptiness check: on the
        # last plan two workers can both pass such a check, and the loser dies
        # on IndexError.  `list.pop` is atomic, so letting it raise is safe.
        try:
            plan = pending.pop()
        except IndexError:
            return

        outcome = run_scene_test(config, plan)

        outStream = f"{logs.msg_any(_STATUS_LABEL[outcome.status], plan.test_id)}"
        if config.verbose == 1:
            if outcome.message:
                outStream += f"\n>>> ===== Reporting for {plan.test_id} \n"
                outStream += outcome.message
                outStream += "\n<<< =====================" + (len(plan.test_id) * "=") + " <<< "
        elif config.verbose >= 2:
            outStream += "\n" + _raw_output(outcome)

        outcomes.append(outcome)
        print(f"({next(executed)}/{total}) " + outStream, flush=True)


def write_summaries(
    outcomes: Sequence[SceneOutcome],
    order: Sequence[ScenePlan],
    test_results_dir: Path,
) -> None:
    """Fill the shared summary files once the run is over (§7.2).

    The three files at the root of the results tree are the only ones several
    scenes write to, so they are appended to from a single thread — that is what
    lets the workers run lock-free.  The per-scene .logs are already on disk,
    each written by the worker that ran the scene (§7.1).

    The outcomes were collected in completion order, so they are re-ordered to
    discovery order first: the summary files then list their scenes in the same
    order from one run to the next, whatever the thread count.  (Their content
    still varies where runSofa prints pointer addresses of its own.)

    @param outcomes Every outcome of the session, in completion order.
    @param order The selected plans, in discovery order.
    @param test_results_dir Results tree to write into, already initialized.
    """
    rank = {plan: index for index, plan in enumerate(order)}
    for outcome in sorted(outcomes, key=lambda o: rank.get(o.plan, len(order))):
        record_summary_entries(
            test_results_dir, outcome.plan, outcome.result, outcome.classification
        )


def _print_summary(outcomes: Sequence[SceneOutcome], test_results_dir: Path, duration : float) -> None:
    """Print the end-of-run summary.

    @param outcomes Every outcome of the session, in completion order.
    @param test_results_dir Results tree the logs and summary files were written to.
    """
    failed = [o for o in outcomes if o.failed]
    passed = sum(1 for o in outcomes if o.passed)
    crashed = [o for o in outcomes if o.crashed]
    skipped = sum(1 for o in outcomes if o.skipped)

    print()
    print("=" * 72)
    print("SOFA scene test summary")
    print(f"  Scenes selected : {len(outcomes)}")
    print(f"  Passed: {passed}  Failed: {len(failed)}  Crashed: {len(crashed)}")
    print(f"  Skipped: {skipped}  Duration: {duration:.3f}s" )
    print(f"  Results dir     : {test_results_dir}")

    if failed:
        print()
        print("Failed scenes:")
        for outcome in sorted(failed, key=lambda o: o.plan.test_id):
            print(f"  {outcome.plan.test_id}")
    if crashed:
        print()
        print("Crashed scenes:")
        for outcome in sorted(crashed, key=lambda o: o.plan.test_id):
            print(f"  {outcome.plan.test_id}")


def run_all(config) -> list[SceneOutcome]:
    """Run a whole session: select the scenes, execute them, write the summaries, report.

    Execution is sequential when a single thread is requested, otherwise workers
    share one job pool, their number being capped at half the number of scenes.
    Each worker writes its own scene's .log as it goes, so a run can be inspected
    while it is still going; only the shared summary files are filled in here,
    afterwards, from this thread.

    @param config Configuration of the run (directories, filters, threads, verbosity).
    @return The outcomes of every scene that ran; empty when nothing was selected.
    """
    start = time.time()

    plans, discovered = selected_scenes(config)
    filtering = bool(config.filters or config.excludes)

    if not plans:
        if filtering:
            print(
                f"No scene ID matched the given filters "
                f"({discovered} scene(s) discovered).",
                file=sys.stderr,
            )
        else:
            print("No scenes discovered — nothing to run.", file=sys.stderr)
        return []

    if filtering:
        print(f"Selected {len(plans)} of {discovered} discovered scene(s).")

    # Done before the run rather than with the writes below, so an unwritable
    # results directory fails now instead of after every scene has been run.
    initialize_report_dir(config.test_results_dir)

    pending = list(plans)  # The job pool the threads drain; `plans` keeps the order.
    outcomes: list[SceneOutcome] = []
    executed = itertools.count(1)
    args = (pending, outcomes, executed, len(plans), config)

    try:
        if config.threads == 1:
            print("Launching in mono-threaded.")
            run_scenes(*args)
        else:
            useThreads = config.threads
            if useThreads > len(plans) // 2:
                useThreads = max(1, len(plans) // 2)

            threads = [
                threading.Thread(target=run_scenes, args=args)
                for _ in range(useThreads - 1)
            ]

            print(f"Launching on {len(threads) + 1} threads.")
            for t in threads:
                t.start()

            run_scenes(*args)

            for t in threads:
                t.join()
    finally:
        # In a finally so that a Ctrl-C still summarises the scenes that did
        # finish; their logs are on disk already.
        write_summaries(outcomes, plans, config.test_results_dir)

    duration_second = time.time()-start

    _print_summary(outcomes, config.test_results_dir, duration_second)
    _write_summary_txt(config.test_results_dir / "summary.txt", outcomes, duration_second)
    return outcomes
