#!/bin/bash 
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/utils.sh
. "$SCRIPT_DIR"/dashboard.sh

# Trap manual abort
getAbort()
{
    echo "TRAP: Abort detected"
    dashboard-notify "status=aborted"
}
trap 'getAbort; exit' SIGHUP SIGINT SIGTERM

# Exit on error
# set -o errexit
# TODO :
# exit 0 = success
# exit 1 = instable
# exit 2 = failure
CODE_SUCCESS=0
CODE_FAILURE=1
CODE_INSTABLE=2
CODE_ABORT=3

usage() {
    echo "Usage: main.sh <build-dir> <src-dir> <compiler> <architecture> <build-type> <build-options>"
}

if [ "$#" -ge 5 ]; then
    if [[ ! -d "$1" ]]; then mkdir -p "$1"; fi
    BUILD_DIR="$(cd "$1" && pwd)"
    SRC_DIR="$(cd "$2" && pwd)"
    
    COMPILER="$3"
    ARCHITECTURE="$4"
    BUILD_TYPE="$5"
    BUILD_OPTIONS="${*:6}"
    
    # sanitize vars
    BUILD_TYPE="${BUILD_TYPE^}"
else
    usage; exit 1
fi

# CI environment variables
dashboard-init "$COMPILER" "$ARCHITECTURE" "$BUILD_TYPE" "$BUILD_OPTIONS"

# VM environment variables
if vm-is-windows && [ -e "$SCRIPT_DIR/env/default-windows" ]; then
    echo "ENV VARS: load $SCRIPT_DIR/env/default-windows"
    . "$SCRIPT_DIR/env/default-windows"
elif [ -e "$SCRIPT_DIR/env/default-unix" ]; then
    echo "ENV VARS: load $SCRIPT_DIR/env/default-unix"
    . "$SCRIPT_DIR/env/default-unix"
fi
if [ -n "$NODE_NAME" ] && [ -e "$SCRIPT_DIR/env/$NODE_NAME" ]; then
    echo "ENV VARS: load node specific $SCRIPT_DIR/env/$NODE_NAME"
    . "$SCRIPT_DIR/env/$NODE_NAME"
fi

# Check [ci-ignore] flag in commit message
commit_message_full="$(git log --pretty=%B -1)"
if [[ "$commit_message_full" == *"[ci-ignore]"* ]]; then
    # Ignore this build
    echo "WARNING: [ci-ignore] detected in commit message, build aborted."
    dashboard-notify "status=aborted"
    exit $CODE_ABORT
fi

# Clean flag files (used to detect aborts)
rm -f "$BUILD_DIR/build-started"
rm -f "$BUILD_DIR/build-finished"
touch "$BUILD_DIR/build-started"

## Configure
dashboard-notify "status=configure"
"$SCRIPT_DIR/configure.sh" "$BUILD_DIR" "$SRC_DIR" "$COMPILER" "$ARCHITECTURE" "$BUILD_TYPE" "$BUILD_OPTIONS"
exit_code="$?"
if [ "$exit_code" = "$CODE_ABORT" ]; then
    dashboard-notify "status=aborted"
    exit $CODE_ABORT
elif [ "$exit_code" = "$CODE_FAILURE" ]; then
    dashboard-notify "status=fail"
    exit $CODE_FAILURE # Build failed
fi

## Compile
dashboard-notify "status=build"
"$SCRIPT_DIR/compile.sh" "$BUILD_DIR" "$COMPILER" "$ARCHITECTURE"
exit_code="$?"
if [ "$exit_code" = "$CODE_SUCCESS" ]; then
    dashboard-notify "status=success"
elif [ "$exit_code" = "$CODE_FAILURE" ]; then
    dashboard-notify "status=fail"
    exit $CODE_FAILURE # Build failed
fi

## [Full build] Count Warnings
if in-array "force-full-build" "$BUILD_OPTIONS"; then
    if vm-is-windows; then
        warning_count=$(grep ' : warning [A-Z]\+[0-9]\+:' "$build_dir/make-output.txt" | sort | uniq | wc -l)
    else
        warning_count=$(grep '^[^:]\+:[0-9]\+:[0-9]\+: warning:' "$build_dir/make-output.txt" | sort -u | wc -l | tr -d ' ')
    fi
    echo "Counted $warning_count compiler warnings."
    dashboard-notify "warnings=$warning_count"
fi

## Unit tests
if in-array "run-unit-tests" "$BUILD_OPTIONS"; then
    dashboard-notify "tests_status=running"

    "$SCRIPT_DIR/tests.sh" run "$BUILD_DIR" "$SRC_DIR"
    "$SCRIPT_DIR/tests.sh" print-summary "$BUILD_DIR" "$SRC_DIR"
    
    tests_suites=$("$SCRIPT_DIR/tests.sh" count-test-suites $BUILD_DIR $SRC_DIR)
    tests_total=$("$SCRIPT_DIR/tests.sh" count-tests $BUILD_DIR $SRC_DIR)
    tests_disabled=$("$SCRIPT_DIR/tests.sh" count-disabled $BUILD_DIR $SRC_DIR)
    tests_failures=$("$SCRIPT_DIR/tests.sh" count-failures $BUILD_DIR $SRC_DIR)
    tests_errors=$("$SCRIPT_DIR/tests.sh" count-errors $BUILD_DIR $SRC_DIR)

    dashboard-notify \
        "tests_suites=$tests_suites" \
        "tests_total=$tests_total" \
        "tests_disabled=$tests_disabled" \
        "tests_failures=$tests_failures" \
        "tests_errors=$tests_errors" 
fi

## Scene tests
if in-array "run-scene-tests" "$BUILD_OPTIONS"; then
    dashboard-notify "scenes_status=running"
    
    "$SCRIPT_DIR/scene-tests.sh" run "$BUILD_DIR" "$SRC_DIR"
    "$SCRIPT_DIR/scene-tests.sh" print-summary "$BUILD_DIR" "$SRC_DIR"
    
    scenes_total=$("$SCRIPT_DIR/scene-tests.sh" count-tests $BUILD_DIR $SRC_DIR)
    scenes_errors=$("$SCRIPT_DIR/scene-tests.sh" count-errors $BUILD_DIR $SRC_DIR)
    scenes_crashes=$("$SCRIPT_DIR/scene-tests.sh" count-crashes $BUILD_DIR $SRC_DIR)
    
    dashboard-notify \
        "scenes_total=$scenes_total" \
        "scenes_errors=$scenes_errors" \
        "scenes_crashes=$scenes_crashes"
fi

touch "$BUILD_DIR/build-finished" # used to detect aborts
