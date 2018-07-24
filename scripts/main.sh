#!/bin/bash
set -o errexit # Exit on error

usage() {
    echo "Usage: main.sh <build-dir> <src-dir> <config> <build-type> <build-options>"
}

if [ "$#" -ge 4 ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    . "$SCRIPT_DIR"/utils.sh
    . "$SCRIPT_DIR"/dashboard.sh
    . "$SCRIPT_DIR"/github.sh

    if [ ! -d "$1" ]; then
        mkdir -p "$1";
    fi
    
    BUILD_DIR="$(cd "$1" && pwd)"
    BUILD_DIR_RESET="$BUILD_DIR"
    SRC_DIR="$(cd "$2" && pwd)"
    SRC_DIR_RESET="$SRC_DIR"

    CONFIG="$3"
    PLATFORM="$(get-platform-from-config "$CONFIG")"
    COMPILER="$(get-compiler-from-config "$CONFIG")"
    ARCHITECTURE="$(get-architecture-from-config "$CONFIG")"
    BUILD_TYPE="$4"
    BUILD_OPTIONS="${*:5}"
    if [ -z "$BUILD_OPTIONS" ]; then
        BUILD_OPTIONS="$(get-build-options)" # use env vars (Jenkins)
    fi
else
    usage; exit 1
fi

# VM environment variables
echo "ENV VARS: load $SCRIPT_DIR/env/default"
. "$SCRIPT_DIR/env/default"
if [ -n "$NODE_NAME" ]; then
    if [ -e "$SCRIPT_DIR/env/$NODE_NAME" ]; then
        echo "ENV VARS: load node specific $SCRIPT_DIR/env/$NODE_NAME"
        . "$SCRIPT_DIR/env/$NODE_NAME"
    else
        echo "ERROR: No config file found for node $NODE_NAME."
        exit 1
    fi
fi

cd "$SRC_DIR"

echo "--------------- main.sh vars ---------------"
echo "BUILD_DIR = $BUILD_DIR"
echo "BUILD_DIR_RESET = $BUILD_DIR_RESET"
echo "SRC_DIR = $SRC_DIR"
echo "CONFIG = $CONFIG"
echo "PLATFORM = $PLATFORM"
echo "COMPILER = $COMPILER"
echo "ARCHITECTURE = $ARCHITECTURE"
echo "BUILD_TYPE = $BUILD_TYPE"
echo "BUILD_OPTIONS = $BUILD_OPTIONS"
echo "--------------------------------------------"

# Clean build dir
if in-array "force-full-build" "$BUILD_OPTIONS"; then
    echo "Force full build ON - cleaning build dir."
    rm -rf "$BUILD_DIR"
    mkdir "$BUILD_DIR"
else
    rm -f "$BUILD_DIR/make-output*.txt"
    rm -rf "$BUILD_DIR/unit-tests"
    rm -rf "$BUILD_DIR/scene-tests"
    rm -rf "$BUILD_DIR/bin"
    rm -rf "$BUILD_DIR/lib"
fi

# Jenkins: create link for Windows jobs (too long path problem)
if vm-is-windows && [ -n "$EXECUTOR_NUMBER" ]; then
    export WORKSPACE_PARENT_WINDOWS="$(cd "$WORKSPACE/.." && pwd -W | sed 's#/#\\#g')"
    cmd //c "if exist j:\%EXECUTOR_NUMBER% rmdir j:\%EXECUTOR_NUMBER%"
    cmd //c "mklink /D j:\%EXECUTOR_NUMBER% %WORKSPACE_PARENT_WINDOWS%"
    export EXECUTOR_LINK_WINDOWS="j:\\$EXECUTOR_NUMBER"
    export EXECUTOR_LINK_WINDOWS_SRC="j:\\$EXECUTOR_NUMBER\src"
    export EXECUTOR_LINK_WINDOWS_BUILD="j:\\$EXECUTOR_NUMBER\build"
    
    SRC_DIR="/j/$EXECUTOR_NUMBER/src"
    BUILD_DIR="/j/$EXECUTOR_NUMBER/build"
fi


# CI environment variables + init
github-export-vars "$PLATFORM" "$COMPILER" "$ARCHITECTURE" "$BUILD_TYPE" "$BUILD_OPTIONS"
dashboard-export-vars "$PLATFORM" "$COMPILER" "$ARCHITECTURE" "$BUILD_TYPE" "$BUILD_OPTIONS"

save-env-vars "GITHUB" "$BUILD_DIR"
save-env-vars "DASH" "$BUILD_DIR"

dashboard-init # Ensure Dashboard line is OK

github-notify "pending" "Building..."
dashboard-notify "status=build"


# Merge PR with target branch
# Fail build if conflict
if [ -n "$DASH_COMMIT_BRANCH" ] && [ -n "$GITHUB_COMMIT_HASH" ] && [ -n "$GITHUB_REPOSITORY" ] && [ -n "$GITHUB_BASE_REF" ] && [ -n "$GITHUB_BASECOMMIT_HASH" ] &&
   [ -x "$(command -v git)" ] && [[ "$(git log -n 1 --pretty=format:"%H")" == "$GITHUB_COMMIT_HASH" ]] &&
   [[ "$DASH_COMMIT_BRANCH" == *"/PR-"* ]]; then
    echo "--------------------------------------------"
    echo "Merging $DASH_COMMIT_BRANCH with latest commit on $GITHUB_BASE_REF: $GITHUB_BASECOMMIT_HASH"
    git config user.email "consortium@sofa-framework.org"
    git config user.name "SOFA Bot"
    git fetch --no-tags --progress "https://github.com/$GITHUB_REPOSITORY.git" "+refs/heads/$GITHUB_BASE_REF:refs/remotes/origin/$GITHUB_BASE_REF"
    git merge "$GITHUB_BASECOMMIT_HASH" > /dev/null || (git merge --abort; exit 1)
    git log -n 1 --pretty=short
    echo "Merge done."
    echo "--------------------------------------------"
fi


# Configure
. "$SCRIPT_DIR/configure.sh" "$BUILD_DIR" "$SRC_DIR" "$CONFIG" "$BUILD_TYPE" "$BUILD_OPTIONS"


# Compile
"$SCRIPT_DIR/compile.sh" "$BUILD_DIR" "$CONFIG"
dashboard-notify "status=success"
github_status="success"
github_message="Build OK."
github-notify "$github_status" "$github_message"

# [Full build] Count Warnings
if in-array "force-full-build" "$BUILD_OPTIONS"; then
    if vm-is-windows; then
        warning_count=$(grep 'warning [A-Z]\+[0-9]\+:' "$BUILD_DIR/make-output.txt" | sort | uniq | wc -l)
    else
        warning_count=$(grep '^[^:]\+:[0-9]\+:[0-9]\+: warning:' "$BUILD_DIR/make-output.txt" | sort -u | wc -l | tr -d ' ')
    fi
    echo "Counted $warning_count compiler warnings."
    dashboard-notify "warnings=$warning_count"
fi

# Reset BUILD_DIR and SRC_DIR for tests (Windows too long path problem)
BUILD_DIR="$BUILD_DIR_RESET"
SRC_DIR="$SRC_DIR_RESET"

# Prepare BUILD_DIR for tests
if vm-is-windows && [ -n "$VM_BOOST_PATH" ] && [ -n "$VM_QT_PATH" ] ; then
    msvc_year="$(get-msvc-year $COMPILER)"
    qt_compiler="msvc${msvc_year}"
    if [[ "$ARCHITECTURE" == "x86" ]]; then
        cp -rf $VM_BOOST_PATH/lib32*/*.dll $BUILD_DIR/bin
        cp -rf $VM_QT_PATH/${qt_compiler}/bin/Qt*.dll $BUILD_DIR/bin
    else
        cp -rf $VM_BOOST_PATH/lib64*/*.dll $BUILD_DIR/bin
        cp -rf $VM_QT_PATH/${qt_compiler}_64/bin/Qt*.dll $BUILD_DIR/bin
    fi
fi

if in-array "run-unit-tests" "$BUILD_OPTIONS" || in-array "run-scene-tests" "$BUILD_OPTIONS"; then
    github_message="${github_message} FIXME:"
fi

# Unit tests
if in-array "run-unit-tests" "$BUILD_OPTIONS"; then
    dashboard-notify "tests_status=running"

    "$SCRIPT_DIR/unit-tests.sh" run "$BUILD_DIR" "$SRC_DIR"
    "$SCRIPT_DIR/unit-tests.sh" print-summary "$BUILD_DIR" "$SRC_DIR"

    tests_suites=$("$SCRIPT_DIR/unit-tests.sh" count-test-suites $BUILD_DIR $SRC_DIR)
    tests_total=$("$SCRIPT_DIR/unit-tests.sh" count-tests $BUILD_DIR $SRC_DIR)
    tests_disabled=$("$SCRIPT_DIR/unit-tests.sh" count-disabled $BUILD_DIR $SRC_DIR)
    tests_failures=$("$SCRIPT_DIR/unit-tests.sh" count-failures $BUILD_DIR $SRC_DIR)
    tests_errors=$("$SCRIPT_DIR/unit-tests.sh" count-errors $BUILD_DIR $SRC_DIR)

    tests_problems=$((tests_failures+tests_errors))
    github_message="${github_message} $tests_problems unit tests"
    if [ $tests_problems -gt 0 ]; then
        github_status="success" # do not fail on tests failure
    fi
    github-notify "$github_status" "$github_message"

    dashboard-notify \
        "tests_status=success" \
        "tests_suites=$tests_suites" \
        "tests_total=$tests_total" \
        "tests_disabled=$tests_disabled" \
        "tests_failures=$tests_failures" \
        "tests_errors=$tests_errors"
fi

# Scene tests
if in-array "run-scene-tests" "$BUILD_OPTIONS"; then
    dashboard-notify "scenes_status=running"
    
    echo "Preventing SofaCUDA from being loaded in VMs."
    if vm-is-windows; then
        plugin_conf="$BUILD_DIR/bin/plugin_list.conf.default"
    else
        plugin_conf="$BUILD_DIR/lib/plugin_list.conf.default"
    fi
    grep -v "SofaCUDA NO_VERSION" "$plugin_conf" > "${plugin_conf}.tmp" && mv "${plugin_conf}.tmp" "$plugin_conf"

    "$SCRIPT_DIR/scene-tests.sh" run "$BUILD_DIR" "$SRC_DIR"
    "$SCRIPT_DIR/scene-tests.sh" print-summary "$BUILD_DIR" "$SRC_DIR"

    scenes_total=$("$SCRIPT_DIR/scene-tests.sh" count-tested-scenes $BUILD_DIR $SRC_DIR)
    scenes_successes=$("$SCRIPT_DIR/scene-tests.sh" count-successes $BUILD_DIR $SRC_DIR)
    scenes_errors=$("$SCRIPT_DIR/scene-tests.sh" count-errors $BUILD_DIR $SRC_DIR)
    scenes_crashes=$("$SCRIPT_DIR/scene-tests.sh" count-crashes $BUILD_DIR $SRC_DIR)

    scenes_problems=$((scenes_errors+scenes_crashes))
    github_message="${github_message}, $scenes_problems scene tests"
    if [ $scenes_problems -gt 0 ]; then
        github_status="success" # do not fail on tests failure
    fi
    github-notify "$github_status" "$github_message"
    
    dashboard-notify \
        "scenes_status=success" \
        "scenes_total=$scenes_total" \
        "scenes_successes=$scenes_successes" \
        "scenes_errors=$scenes_errors" \
        "scenes_crashes=$scenes_crashes"

    # Clamping warning and error files to avoid Jenkins overflow
    "$SCRIPT_DIR/scene-tests.sh" clamp-warnings "$BUILD_DIR" "$SRC_DIR" 5000
    "$SCRIPT_DIR/scene-tests.sh" clamp-errors "$BUILD_DIR" "$SRC_DIR" 5000
fi

if in-array "force-full-build" "$BUILD_OPTIONS"; then
    mv "$BUILD_DIR/make-output.txt" "$BUILD_DIR/make-output-fullbuild-$COMPILER.txt"
fi
