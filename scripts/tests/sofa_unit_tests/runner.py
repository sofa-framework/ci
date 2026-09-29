"""Vanilla sequential runner: discovery -> per-binary execution -> live status
line -> session-end reports. No pytest involved (deliberate deviation from
the pytest-based harness described in SPEC.md/CLAUDE.md — see CLAUDE.md's
deviation notice). Replaces the former plugin.py + _test_module.py.
"""
from __future__ import annotations

import os
import time
from pathlib import Path
from typing import List, Tuple, Dict

import threading
from .utils import SubList, Logs

from . import classify, discovery, execution, isolation, paths, reporting
from .config import Config


global executedTests, totalTests

def _selected_binaries(cfg: Config) -> List[Tuple[str, Path]]:
    binaries = discovery.discover_binaries(cfg.build_dir)

    selected: List[Tuple[str, Path]] = []
    for binary in binaries:
        name = discovery.test_name_for_path(binary)
        if cfg.filter is not None and not cfg.filter.search(name):
            continue
        if cfg.exclude is not None and cfg.exclude.search(name):
            continue
        selected.append((name, binary))
    return selected


def __print_summary(outcomes: reporting.Counts, test_results_dir: Path, failed_tests_names: Dict, crashed_tests_names: Dict) -> None:

    passed = outcomes.test_total - outcomes.failures - outcomes.crashes

    print()
    print("=" * 72)
    print("SOFA unit test summary")
    print(f"  Unit tests ran : {outcomes.test_total}")
    print(f"  Passed: {passed}  Failed: {outcomes.failures}  Crash: {outcomes.crashes}")
    print(f"  Results dir     : {test_results_dir}")

    if outcomes.failures:
        print()
        print("Failed tests:")
        for tests_name in failed_tests_names:
            print(f"  {tests_name}")
            for case_name in failed_tests_names[tests_name]:
                print(f"    {case_name}")
    if outcomes.crashes:
        print()
        print("Crashed tests:")
        for tests_name in crashed_tests_names:
            print(f"  {tests_name}")
            for case_name in crashed_tests_names[tests_name]:
                print(f"    {case_name}")



def run_binary(
    test_name: str,
    binary_path: Path,
    *,
    results_dir: Path,
    timeout: int,
    is_windows: bool,
) -> str:
    """Run one binary, isolating it on crash, and return its status
    ("passed" / "failed" / "crashed") (spec §5, §7, §9)."""
    binary_dir = paths.binary_dir(results_dir, test_name)
    execution.execute_and_record(
        binary_path,
        output_path=paths.output_path(binary_dir),
        command_line_path=paths.command_line_path(binary_dir),
        exit_status_path=paths.exit_status_path(binary_dir),
        gtest_output_xml=paths.report_xml_path(binary_dir),
        timeout=timeout,
        is_windows=is_windows,
    )

    parsed = classify.parse_report(paths.report_xml_path(binary_dir))
    if parsed is None:
        # Fire-and-forget: populates subtests/ artifacts for reporting.build_reports
        # to re-read later. Its outcome does not change this binary's own status,
        # which is "crashed" whenever the top-level XML is absent (spec §7).
        isolation.isolate(binary_path, binary_dir=binary_dir, timeout=timeout, is_windows=is_windows)
        return "crashed"
    if parsed.passed:
        return "passed"
    return "failed"

def run_binaries(selected, is_windows, results_dir, timeout, verbose ):
    global executedTests, totalTests

    logs = Logs()

    while len(selected) > 0 :
        test_name, binary_path = selected.pop()

        status = run_binary(
            test_name,
            binary_path,
            results_dir=results_dir,
            timeout=timeout,
            is_windows=is_windows,
        )
        outStream = f"{logs.msg_any(status.upper(),test_name)}"
        if(verbose == 1):
            temp_failed, temp_crash, _, _, _, _, _ = reporting.getInsights(paths.binary_dir(results_dir, test_name) , test_name, binary_path, timeout, is_windows)

            if((len(temp_failed) + len(temp_crash)) >0):
                outStream += f"\n>>> ===== Reporting for {test_name} \n"
                if(len(temp_failed) > 0):
                    outStream += "\n".join(temp_failed)
                    outStream += "\n"

                if(len(temp_crash) > 0):
                    outStream += "\n".join(temp_crash)
                    outStream += "\n"

                outStream += f"<<< =====================" + (len(test_name) * "=") + " <<< "

        elif(verbose == 2):

            binary_dir = paths.binary_dir(results_dir, test_name)
            output_path = paths.output_path(binary_dir)
            data = Path(output_path).read_text()
            outStream += "\n" + data

        executedTests +=1
        print(f"({executedTests}/{totalTests}) " + outStream)


def run_all(cfg: Config) -> reporting.Counts:
    """Discover, run every selected binary sequentially, stream a live status
    line per binary as it finishes, then write the session-end reports
    (spec §4, §5, §8). --threads is not consulted here — see __main__.main."""
    selected = _selected_binaries(cfg)
    popableSelected = selected.copy() #This list will be used as a job pool bu the threads to unpack

    is_windows = os.name == "nt"
    start = time.time()
    global executedTests, totalTests
    executedTests = 0
    totalTests = len(selected)

    if(cfg.threads == 1 ):
        print(f"Launching in mono-threaded.")

        run_binaries(popableSelected, is_windows, cfg.results_dir, cfg.timeout, cfg.verbose)

    else:
        useThreads = cfg.threads
        if( useThreads > len(selected)//2):
            useThreads = len(selected)//2


        threads = []
        for i in range(useThreads - 1):
            t = threading.Thread(target=run_binaries, args=(popableSelected,is_windows, cfg.results_dir, cfg.timeout, cfg.verbose))
            threads.append(t)

        print(f"Launching on {len(threads) +1} threads.")
        for t in threads:
            t.start()

        run_binaries(popableSelected,is_windows, cfg.results_dir, cfg.timeout, cfg.verbose)

        for t in threads:
            t.join()

    count, failed_tests_names, crashed_tests_names = reporting.build_reports(
        cfg.results_dir,
        selected,
        duration_seconds=time.time() - start,
        timeout=cfg.timeout,
        is_windows=is_windows,
    )
    __print_summary(count, cfg.results_dir, failed_tests_names, crashed_tests_names )

    return count
