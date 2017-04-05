#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/functions.sh

# COPY PASTE THIS IN JENKINS JOB

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
    
    CI_COMPILER="$3"
    CI_ARCH="$4"
    CI_BUILD_TYPE="$5"
    CI_BUILD_OPTIONS="${*:6}"
else
    usage; exit 1
fi

# Setup Windows environment variables
if vm-is-windows; then
    . /c/setup-vm-env.sh
fi

# hash=$(git log --pretty=format:'%H' -1)
# author=$(git log --pretty=format:'%an' -1)
# author_email=$(git log --pretty=format:'%aE' -1)
# committer=$(git log --pretty=format:'%cn' -1)
# committer_email=$(git log --pretty=format:'%cE' -1)
# date=$(git log --pretty=format:%ct -1)
# subject=$(git log --pretty=format:'%s' -1)
# subject_full=$(git log --pretty=%B -1)

# Check ci-ignore flag in commit message
commit_message=$(git log --pretty=%B -1)
if [[ "$commit_message" == *"[ci-ignore]"* ]]; then
    # Ignore this build
    echo "WARNING: [ci-ignore] detected, build aborted."
    exit $CODE_ABORT
fi

## Create dashboard build line
notify-dashboard "platform=$CI_PLATFORM" "compiler=$CI_COMPILER" "options=$CI_OPTIONS" "build_url=$BUILD_URL" "job_url=$JOB_URL"

# Clean flag files (used to detect aborts)
rm -f "$BUILD_DIR/build-started"
rm -f "$BUILD_DIR/build-finished"
touch "$BUILD_DIR/build-started"

## Configure
notify-dashboard "status=configure"
"$SCRIPT_DIR/configure.sh" "$BUILD_DIR" "$SRC_DIR" "$CI_COMPILER" "$CI_ARCH" "$CI_BUILD_TYPE" "$CI_BUILD_OPTIONS"
exit_code="$?"
if [ "$exit_code" = "$CODE_ABORT" ]; then
    exit $CODE_ABORT
elif [ "$exit_code" = "$CODE_FAILURE" ]; then
    notify-dashboard "status=fail"
    exit $CODE_FAILURE # Build failed
fi

## Compile
notify-dashboard "status=build"
"$SCRIPT_DIR/compile.sh" "$BUILD_DIR" "$CI_COMPILER" "$CI_ARCH"
exit_code="$?"
if [ "$exit_code" = "$CODE_SUCCESS" ]; then
    notify-dashboard "status=success"
elif [ "$exit_code" = "$CODE_FAILURE" ]; then
    notify-dashboard "status=fail"
    exit $CODE_FAILURE # Build failed
fi

## [Full build] Count Warnings
if in-array "force-full-build" "$CI_BUILD_OPTIONS"; then
    if vm-is-windows; then
        warning_count=$(grep ' : warning [A-Z]\+[0-9]\+:' "$build_dir/make-output.txt" | sort | uniq | wc -l)
    else
        warning_count=$(grep '^[^:]\+:[0-9]\+:[0-9]\+: warning:' "$build_dir/make-output.txt" | sort -u | wc -l | tr -d ' ')
    fi
    echo "$warning_count"
    echo "Counted $warning_count compiler warnings."
    notify-dashboard "fullbuild=true" "warnings=$warning_count"
fi

## Unit tests
if [[ -n "$CI_UNIT_TESTS" ]]; then
    notify-dashboard "tests_status=running"

    "$SCRIPT_DIR/tests.sh" run "$BUILD_DIR" "$SRC_DIR"
    "$SCRIPT_DIR/tests.sh" print-summary "$BUILD_DIR" "$SRC_DIR"
    
    tests_suites=$("$SCRIPT_DIR/tests.sh" count-test-suites $BUILD_DIR $SRC_DIR)
    tests_total=$("$SCRIPT_DIR/tests.sh" count-tests $BUILD_DIR $SRC_DIR)
    tests_disabled=$("$SCRIPT_DIR/tests.sh" count-disabled $BUILD_DIR $SRC_DIR)
    tests_failures=$("$SCRIPT_DIR/tests.sh" count-failures $BUILD_DIR $SRC_DIR)
    tests_errors=$("$SCRIPT_DIR/tests.sh" count-errors $BUILD_DIR $SRC_DIR)

    notify-dashboard \
        "tests_suites=$tests_suites" \
        "tests_total=$tests_total" \
        "tests_disabled=$tests_disabled" \
        "tests_failures=$tests_failures" \
        "tests_errors=$tests_errors" 
fi

## Scene tests
if [[ -n "$CI_SCENE_TESTS" ]]; then
    notify-dashboard "scenes_status=running"
    
    "$SCRIPT_DIR/scene-tests.sh" run "$BUILD_DIR" "$SRC_DIR"
    "$SCRIPT_DIR/scene-tests.sh" print-summary "$BUILD_DIR" "$SRC_DIR"
    
    scenes_total=$("$SCRIPT_DIR/scene-tests.sh" count-tests $BUILD_DIR $SRC_DIR)
    scenes_errors=$("$SCRIPT_DIR/scene-tests.sh" count-errors $BUILD_DIR $SRC_DIR)
    scenes_crashes=$("$SCRIPT_DIR/scene-tests.sh" count-crashes $BUILD_DIR $SRC_DIR)
    
    notify-dashboard \
        "scenes_total=$scenes_total" \
        "scenes_errors=$scenes_errors" \
        "scenes_crashes=$scenes_crashes"
fi

touch "$BUILD_DIR/build-finished" # used to detect aborts
