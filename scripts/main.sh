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


# Set VM environment variables
load-vm-env
echo "[BEGIN] Init ($(time-date))"
time_millisec_init_begin="$(time-millisec)"

# Clean build dir
rm -f  $BUILD_DIR/make-output*.txt $BUILD_DIR/build-result $BUILD_DIR/full-build
rm -rf $BUILD_DIR/unit-tests* $BUILD_DIR/scene-tests* $BUILD_DIR/regression-tests*
rm -rf $BUILD_DIR/bin $BUILD_DIR/lib $BUILD_DIR/install $BUILD_DIR/external_directories
rm -rf $BUILD_DIR/_CPack_Packages $BUILD_DIR/CPackConfig.cmake
rm -f  $BUILD_DIR/SOFA_*.exe $BUILD_DIR/SOFA_*.run $BUILD_DIR/SOFA_*.dmg $BUILD_DIR/SOFA_*.zip
# TODO: find out why we have these files polluting BUILD_DIR
rm -rf $BUILD_DIR/cube5x5x5* $BUILD_DIR/energy.txt $BUILD_DIR/*.vtu $BUILD_DIR/exporter1.* \
       $BUILD_DIR/monitor_* $BUILD_DIR/outfile.* $BUILD_DIR/particleGravity* \
       $BUILD_DIR/PluginManager_test* $BUILD_DIR/Springtest_positions* $BUILD_DIR/test.*
# TEMPORARY: remove huge core dumps on CentOS and disable them
# TODO: fix the issue and remove this
if vm-is-centos; then
    rm -f $BUILD_DIR/core.*
    ulimit -c 0
fi
# TEMPORARY: remove SofaPython3 files linked to the error
# Submodule_Simulation.cpp.o: file not recognized: File format not recognized
rm -rf $BUILD_DIR/applications/plugins/SofaPython3/bindings/Sofa

# Choose between incremental build and full build
full_build=""
if in-array "force-full-build" "$BUILD_OPTIONS"; then
    full_build="Full build forced."
    echo "Force full build ON - cleaning build dir."
    rm -rf "$BUILD_DIR" || exit 1  # build dir cannot be deleted for some reason on a Windows VM, to be fixed.
    mkdir "$BUILD_DIR"
elif [ ! -e "$BUILD_DIR/CMakeCache.txt" ]; then
    full_build="No previous build detected."
    export DASH_FULLBUILD="true" # Force Dashboard fullbuild param
fi
if [ -n "$full_build" ]; then
    echo "true" > "$BUILD_DIR/full-build"
    echo "Starting a full build. ($full_build)"
else
    echo "Starting an incremental build"
fi

# Notify GitHub and Dashboard
if [ -n "$CI_REPORT_TO_GITHUB" ] && [ -n "$CI_REPORT_TO_DASHBOARD" ]; then
    # CI environment variables + init
    github-export-vars "$PLATFORM" "$COMPILER" "$ARCHITECTURE" "$BUILD_TYPE" "$BUILD_OPTIONS"
    dashboard-export-vars "$PLATFORM" "$COMPILER" "$ARCHITECTURE" "$BUILD_TYPE" "$BUILD_OPTIONS"

    save-env-vars "GITHUB" "$BUILD_DIR"
    save-env-vars "DASH" "$BUILD_DIR"

    # dashboard-init # Ensure Dashboard line is OK

    GITHUB_TARGET_URL_OLD="$GITHUB_TARGET_URL"
    export GITHUB_TARGET_URL="${GITHUB_TARGET_URL}console"
    github-notify "pending" "Building..."
    export GITHUB_TARGET_URL="$GITHUB_TARGET_URL_OLD"

    dashboard-notify "status=build"
fi

time_millisec_init_end="$(time-millisec)"
time_sec_init="$(time-elapsed-sec $time_millisec_init_begin $time_millisec_init_end)"
echo "[END] Init ($(time-date)) - took $time_sec_init seconds"


# Moving to src dir
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
echo "----------------- VM config -----------------"
echo "-- PATH"
echo "$PATH"
echo "-- CMake"
cmake --version
echo "-- Generator"
if [ -x "$(command -v ninja)" ]; then
    echo "ninja $(ninja --version)"
elif vm-is-windows; then
    cmd //c "nmake /HELP"
else
    make --version
fi
echo "-- Compiler"
if vm-is-windows; then
    if [ -x "$(command -v vswhere)" ]; then
        cmd //c "vswhere -latest -products * -property displayName"
    else
        echo "Visual Studio $(get-msvc-year "$COMPILER")"
    fi
elif vm-is-macos; then
    echo "AppleClang version: $(clang --version | grep -o clang-[^\)]*)"
    echo "AppleClang install dir: $(clang --version | grep InstalledDir)"

    echo "AppleClang/Clang correspondance: https://en.wikipedia.org/wiki/Xcode#Xcode_7.0_-_12.x_%28since_Free_On-Device_Development%29"
    echo "Example: AppleClang 1001.0.46.3 is based on Clang 7.0.0"

    if [ -x "$(command -v xcodebuild)" ]; then
        echo "Xcode version: $(xcodebuild -version)"
    fi
    if [ -x "$(command -v xcode-select)" ]; then
        echo "Xcode install dir: $(xcode-select -p)"
    fi
else
    echo "$(${COMPILER%-*} --version)" # gcc-5.8 -> gcc
fi
echo "-- Qt"
if [ -n "$VM_QT_PATH" ]; then
    echo -n "Qt "
    basename "$VM_QT_PATH"
elif [ -x "$(command -v qmake)" ]; then
    qmake --version
else
    echo "Don't know how to get Qt version."
fi
echo "--------------------------------------------"

echo "[BEGIN] Git work ($(time-date))"
time_millisec_git_begin="$(time-millisec)"

# Wait for git to be available
if [ `ps -elf | grep -c git` -gt 1 ]; then
    echo "Waiting for git 10s ..."
    sleep 10
fi
if [ `ps -elf | grep -c git` -gt 1 ]; then
    echo "Waiting for git 30s ..."
    sleep 30
fi
if [ `ps -elf | grep -c git` -gt 1 ]; then
    echo "Waiting for git 60s ..."
    sleep 60
fi
if [ `ps -elf | grep -c git` -gt 1 ]; then
    echo "Still no git available, let's try to run anyway."
fi


# Git config (needed by CMake ExternalProject)
if ! git config --get user.name; then
    git config --system user.name 'SOFA Bot' > /dev/null 2>&1 ||
        git config --global user.name 'SOFA Bot' > /dev/null 2>&1 ||
        git config user.name 'SOFA Bot' > /dev/null 2>&1 ||
        echo "WARNING: cannot setup git config"
fi
if ! git config --get user.email; then
    git config --system user.email '<>' > /dev/null 2>&1 ||
        git config --global user.email '<>' > /dev/null 2>&1 ||
        git config user.email '<>' > /dev/null 2>&1 ||
        echo "WARNING: cannot setup git config"
fi


# Jenkins: create link for Windows jobs (too long path problem)
if vm-is-windows && [ -n "$EXECUTOR_NUMBER" ]; then
    if [[ "$WORKSPACE" == *"src" ]]; then
        export WORKSPACE_PARENT_WINDOWS="$(cd "$WORKSPACE/.." && pwd -W | sed 's#/#\\#g')"
    else
        export WORKSPACE_PARENT_WINDOWS="$(cd "$WORKSPACE" && pwd -W | sed 's#/#\\#g')"
    fi
    cmd //c "if exist J:\%EXECUTOR_NUMBER% rmdir /S /Q J:\%EXECUTOR_NUMBER%"
    cmd //c "mklink /D J:\%EXECUTOR_NUMBER% %WORKSPACE_PARENT_WINDOWS%"
    export EXECUTOR_LINK_WINDOWS="J:\\$EXECUTOR_NUMBER"
    export EXECUTOR_LINK_WINDOWS_SRC="J:\\$EXECUTOR_NUMBER\src"
    export EXECUTOR_LINK_WINDOWS_BUILD="J:\\$EXECUTOR_NUMBER\build"

    SRC_DIR="/J/$EXECUTOR_NUMBER/src"
    BUILD_DIR="/J/$EXECUTOR_NUMBER/build"
fi


# Reset external repositories in src dir
find * -name '.git' | while read external_repo_git; do
    external_repo="$(dirname $external_repo_git)"
    if [ -d $external_repo ]; then
        echo "Cleaning external repository: $external_repo"
        rm -rf $external_repo
    fi
done
git reset --hard


# Checkout the right commit
if [ -n "$GITHUB_COMMIT_HASH" ] && [[ "$GITHUB_COMMIT_HASH" != "$(git log -n 1 --pretty=format:"%H")" ]]; then
    echo "--------------------------------------------"
    echo "Checkouting the right commit: $GITHUB_COMMIT_HASH"
    git fetch --all > /dev/null
    git checkout --force "$GITHUB_COMMIT_HASH" > /dev/null
    echo "Checkout done."
    echo "--------------------------------------------"
fi


# Merge PR with target branch
# Fail build if conflict
if [ -n "$DASH_COMMIT_BRANCH" ] && [ -n "$GITHUB_COMMIT_HASH" ] && [ -n "$GITHUB_REPOSITORY" ] && [ -n "$GITHUB_BASE_REF" ] && [ -n "$GITHUB_BASECOMMIT_HASH" ] &&
   [ -x "$(command -v git)" ] && [[ "$(git log -n 1 --pretty=format:"%H")" == "$GITHUB_COMMIT_HASH" ]] &&
   [[ "$DASH_COMMIT_BRANCH" == *"/PR-"* ]]; then
    echo "--------------------------------------------"
    echo "Merging $DASH_COMMIT_BRANCH with this commit of base $GITHUB_BASE_REF: $GITHUB_BASECOMMIT_HASH"
    git fetch --no-tags "https://github.com/$GITHUB_REPOSITORY.git" "+refs/heads/$GITHUB_BASE_REF:refs/remotes/origin/$GITHUB_BASE_REF"
    git merge "$GITHUB_BASECOMMIT_HASH" || (
        echo "Something went wrong during merge, aborting..."
        git merge --abort
        exit 1
        )
    git log -n 1 --pretty=short
    echo "Merge done."
    echo "--------------------------------------------"
fi


# Handle [ci-depends-on]
if [[ "$DASH_COMMIT_BRANCH" == *"/PR-"* ]]; then
    # Get info about this PR from GitHub API
    pr_id="${DASH_COMMIT_BRANCH#*-}"
    pr_json="$(github-get-pr-json "$pr_id")"
    pr_description="$(github-get-pr-description "$pr_json")"

    while read dependency; do
        dependency="${dependency%$'\r'}" # remove \r from dependency
        dependency_url="$(echo "$dependency" | sed 's:\[ci-depends-on \(.*\)\]:\1:g')"
        if ! curl -sSf "$dependency_url" > /dev/null; then
            # bad url
            continue
        fi

        dependency_json="$(github-get-pr-json "$dependency_url")"
        dependency_project_name="$(github-get-pr-project-name "$dependency_json")"
        dependency_project_url="$(github-get-pr-project-url "$dependency_json")"
        dependency_merge_commit="$(github-get-pr-merge-commit "$dependency_json")"

        external_project_file="$(find "$SRC_DIR" -wholename "*/$dependency_project_name/ExternalProjectConfig.cmake.in")"
        if [ -e "$external_project_file" ]; then
            # Force replace GIT_REPOSITORY and GIT_TAG
            sed -i'.bak' 's,GIT_REPOSITORY .*,GIT_REPOSITORY '"$dependency_project_url"',g' "$external_project_file" && rm -f "$external_project_file.bak"
            sed -i'.bak' 's,GIT_TAG .*,GIT_TAG '"$dependency_merge_commit"',g' "$external_project_file" && rm -f "$external_project_file.bak"
        fi
        echo "[ci-depends-on] Replacing $external_project_file with"
        echo "    GIT_REPOSITORY $dependency_project_url"
        echo "    GIT_TAG $dependency_merge_commit"
    done < <( echo "$pr_description" | grep '\[ci-depends-on' )
fi


time_millisec_git_end="$(time-millisec)"
time_sec_git="$(time-elapsed-sec $time_millisec_git_begin $time_millisec_git_end)"
echo "[END] Git work ($(time-date)) - took $time_sec_git seconds"


# Configure
echo "[BEGIN] Configure ($(time-date))"
time_millisec_configure_begin="$(time-millisec)"
. "$SCRIPT_DIR/configure.sh" "$BUILD_DIR" "$SRC_DIR" "$CONFIG" "$BUILD_TYPE" "$BUILD_OPTIONS"
time_millisec_configure_end="$(time-millisec)"
time_sec_configure="$(time-elapsed-sec $time_millisec_configure_begin $time_millisec_configure_end)"
echo "[END] Configure ($(time-date)) - took $time_sec_configure seconds"


# Regression dir
# WARNING: source files exist only after configure, they are fetched by CMake
if in-array "run-regression-tests" "$BUILD_OPTIONS"; then # Jenkins
    if [ -n "$WORKSPACE" ] && [ -d "$SRC_DIR/applications/projects/Regression" ]; then
        if vm-is-windows; then
            export REGRESSION_DIR="$(cd "$SRC_DIR/applications/projects/Regression" && pwd -W)"
        else
            export REGRESSION_DIR="$(cd "$SRC_DIR/applications/projects/Regression" && pwd)"
        fi
    elif [ -z "$REGRESSION_DIR" ]; then # not Jenkins and no REGRESSION_DIR
        echo "WARNING: run-regression-tests option needs REGRESSION_DIR env var, regression tests will NOT be performed."
    fi
fi


# Compile
echo "[BEGIN] Build ($(time-date))"
time_millisec_build_begin="$(time-millisec)"
"$SCRIPT_DIR/compile.sh" "$BUILD_DIR" "$CONFIG"
dashboard-notify "status=success"
github_status="success"
github_message="Build OK."
github-notify "$github_status" "$github_message"
time_millisec_build_end="$(time-millisec)"
time_sec_build="$(time-elapsed-sec $time_millisec_build_begin $time_millisec_build_end)"
echo "[END] Build ($(time-date)) - took $time_sec_build seconds"


echo "[BEGIN] Post build ($(time-date))"
time_millisec_postbuild_begin="$(time-millisec)"
# [Full build] Count Warnings
if [ -e "$BUILD_DIR/full-build" ]; then
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

# Remove SofaCUDA and SofaPython from plugin_list.conf.default
echo "Removing SofaCUDA and SofaPython from plugin_list.conf.default"
if vm-is-windows; then
    plugin_conf="$BUILD_DIR/bin/plugin_list.conf.default"
else
    plugin_conf="$BUILD_DIR/lib/plugin_list.conf.default"
fi
grep -v "SofaCUDA " "$plugin_conf" > "${plugin_conf}.tmp" && mv "${plugin_conf}.tmp" "$plugin_conf"
grep -v "SofaPython " "$plugin_conf" > "${plugin_conf}.tmp" && mv "${plugin_conf}.tmp" "$plugin_conf"

time_millisec_postbuild_end="$(time-millisec)"
time_sec_postbuild="$(time-elapsed-sec $time_millisec_postbuild_begin $time_millisec_postbuild_end)"
echo "[END] Post build ($(time-date)) - took $time_sec_postbuild seconds"

# Unit tests
if in-array "run-unit-tests" "$BUILD_OPTIONS"; then
    echo "[BEGIN] Unit tests ($(time-date))"
    time_millisec_unittests_begin="$(time-millisec)"

    tests_status="running"
    dashboard-notify "tests_status=$tests_status"
    echo "$tests_status" > "$BUILD_DIR/unit-tests.status"

    "$SCRIPT_DIR/unit-tests.sh" run "$BUILD_DIR" "$SRC_DIR"
    "$SCRIPT_DIR/unit-tests.sh" print-summary "$BUILD_DIR" "$SRC_DIR"

    tests_status="done" # TODO: handle script crash
    echo "$tests_status" > "$BUILD_DIR/unit-tests.status"

    tests_suites=$("$SCRIPT_DIR/unit-tests.sh" count-test-suites $BUILD_DIR $SRC_DIR)
    tests_total=$("$SCRIPT_DIR/unit-tests.sh" count-tests $BUILD_DIR $SRC_DIR)
    tests_disabled=$("$SCRIPT_DIR/unit-tests.sh" count-disabled $BUILD_DIR $SRC_DIR)
    tests_failures=$("$SCRIPT_DIR/unit-tests.sh" count-failures $BUILD_DIR $SRC_DIR)
    tests_errors=$("$SCRIPT_DIR/unit-tests.sh" count-errors $BUILD_DIR $SRC_DIR)
    tests_duration=$("$SCRIPT_DIR/unit-tests.sh" count-durations $BUILD_DIR $SRC_DIR)

    tests_problems=$(( tests_failures + tests_errors ))
    github_message="${github_message} $tests_problems unit"
    if [ $tests_problems -gt 1 ]; then
        github_message="${github_message}s"
    fi
    github_status="success" # do not fail on tests failure
    github-notify "$github_status" "$github_message"

    dashboard-notify \
        "tests_status=$tests_status" \
        "tests_suites=$tests_suites" \
        "tests_total=$tests_total" \
        "tests_disabled=$tests_disabled" \
        "tests_failures=$tests_failures" \
        "tests_errors=$tests_errors" \
        "tests_duration=$tests_duration"

    time_millisec_unittests_end="$(time-millisec)"
    time_sec_unittests="$(time-elapsed-sec $time_millisec_unittests_begin $time_millisec_unittests_end)"
    echo "[END] Unit tests ($(time-date)) - took $time_sec_unittests seconds"
else
    echo "disabled" > "$BUILD_DIR/unit-tests.status"
fi

# Scene tests
if in-array "run-scene-tests" "$BUILD_OPTIONS"; then
    echo "[BEGIN] Scene tests ($(time-date))"
    time_millisec_scenetests_begin="$(time-millisec)"

    scenes_status="running"
    dashboard-notify "scenes_status=$scenes_status"
    echo "$scenes_status" > "$BUILD_DIR/scene-tests.status"

    "$SCRIPT_DIR/scene-tests.sh" run "$BUILD_DIR" "$SRC_DIR"
    "$SCRIPT_DIR/scene-tests.sh" print-summary "$BUILD_DIR" "$SRC_DIR"

    scenes_status="done" # TODO: handle script crash
    echo "$scenes_status" > "$BUILD_DIR/scene-tests.status"

    scenes_total=$("$SCRIPT_DIR/scene-tests.sh" count-tested-scenes $BUILD_DIR $SRC_DIR)
    scenes_successes=$("$SCRIPT_DIR/scene-tests.sh" count-successes $BUILD_DIR $SRC_DIR)
    scenes_errors=$("$SCRIPT_DIR/scene-tests.sh" count-errors $BUILD_DIR $SRC_DIR)
    scenes_crashes=$("$SCRIPT_DIR/scene-tests.sh" count-crashes $BUILD_DIR $SRC_DIR)
    scenes_duration=$("$SCRIPT_DIR/scene-tests.sh" count-durations $BUILD_DIR $SRC_DIR)

    scenes_problems=$(( scenes_errors + scenes_crashes ))
    github_message="${github_message}, $scenes_problems scene"
    if [ $scenes_problems -gt 1 ]; then
        github_message="${github_message}s"
    fi
    github_status="success" # do not fail on tests failure
    github-notify "$github_status" "$github_message"

    dashboard-notify \
        "scenes_status=$scenes_status" \
        "scenes_total=$scenes_total" \
        "scenes_successes=$scenes_successes" \
        "scenes_errors=$scenes_errors" \
        "scenes_crashes=$scenes_crashes" \
        "scenes_duration=$scenes_duration"

    # Clamping warning and error files to avoid Jenkins overflow
    "$SCRIPT_DIR/scene-tests.sh" clamp-warnings "$BUILD_DIR" "$SRC_DIR" 5000
    "$SCRIPT_DIR/scene-tests.sh" clamp-errors "$BUILD_DIR" "$SRC_DIR" 5000

    time_millisec_scenetests_end="$(time-millisec)"
    time_sec_scenetests="$(time-elapsed-sec $time_millisec_scenetests_begin $time_millisec_scenetests_end)"
    echo "[END] Scene tests ($(time-date)) - took $time_sec_scenetests seconds"
else
    echo "disabled" > "$BUILD_DIR/scene-tests.status"
fi

# Regression tests
if in-array "run-regression-tests" "$BUILD_OPTIONS" && [ -n "$REGRESSION_DIR" ]; then
    echo "[BEGIN] Regression tests ($(time-date))"
    time_millisec_regressiontests_begin="$(time-millisec)"

    regressions_status="running"
    dashboard-notify "regressions_status=$regressions_status"
    echo "$regressions_status" > "$BUILD_DIR/regression-tests.status"

    references_dir="$REGRESSION_DIR/references"

    "$SCRIPT_DIR/unit-tests.sh" run "$BUILD_DIR" "$SRC_DIR" "$references_dir"
    "$SCRIPT_DIR/unit-tests.sh" print-summary "$BUILD_DIR" "$SRC_DIR" "$references_dir"

    regressions_status="done" # TODO: handle script crash
    echo "$regressions_status" > "$BUILD_DIR/regression-tests.status"

    regressions_suites=$("$SCRIPT_DIR/unit-tests.sh" count-test-suites $BUILD_DIR $SRC_DIR $references_dir)
    regressions_total=$("$SCRIPT_DIR/unit-tests.sh" count-tests $BUILD_DIR $SRC_DIR $references_dir)
    regressions_disabled=$("$SCRIPT_DIR/unit-tests.sh" count-disabled $BUILD_DIR $SRC_DIR $references_dir)
    regressions_failures=$("$SCRIPT_DIR/unit-tests.sh" count-failures $BUILD_DIR $SRC_DIR $references_dir)
    regressions_errors=$("$SCRIPT_DIR/unit-tests.sh" count-errors $BUILD_DIR $SRC_DIR $references_dir)
    regressions_duration=$("$SCRIPT_DIR/unit-tests.sh" count-durations $BUILD_DIR $SRC_DIR $references_dir)

    regressions_problems=$(( regressions_failures + regressions_errors ))
    github_message="${github_message}, $regressions_problems regression"
    if [ $regressions_problems -gt 1 ]; then
        github_message="${github_message}s"
    fi
    github_status="success" # do not fail on tests failure
    github-notify "$github_status" "$github_message"

    dashboard-notify \
        "regressions_status=$regressions_status" \
        "regressions_suites=$regressions_suites" \
        "regressions_total=$regressions_total" \
        "regressions_disabled=$regressions_disabled" \
        "regressions_failures=$regressions_failures" \
        "regressions_errors=$regressions_errors" \
        "regressions_duration=$regressions_duration"

    time_millisec_regressiontests_end="$(time-millisec)"
    time_sec_regressiontests="$(time-elapsed-sec $time_millisec_regressiontests_begin $time_millisec_regressiontests_end)"
    echo "[END] Regression tests ($(time-date)) - took $time_sec_regressiontests seconds"
else
    echo "disabled" > "$BUILD_DIR/regression-tests.status"
fi

if [ -e "$BUILD_DIR/full-build" ]; then
    mv "$BUILD_DIR/make-output.txt" "$BUILD_DIR/make-output-fullbuild-$COMPILER.txt"
fi

# TEMPORARY: remove huge core dumps on CentOS
# TODO: fix the issue and remove this
if vm-is-centos; then
    rm -f $BUILD_DIR/core.*
fi
