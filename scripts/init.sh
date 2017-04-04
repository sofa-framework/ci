#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/functions.sh

# This script creates the build directory if it does not exist.  If the build
# already exists, the script checks if it is possible to make an incremental
# build.

## Significant environnement variables:
# - CI_FORCE_FULL_BUILD       Prevent an incremental build

# Exit on error
set -o errexit


### Checks

usage() {
    echo "Usage: init.sh <build-dir> <src-dir> <build-options>"
}

if [[ "$#" = 3 ]]; then
    BUILD_DIR="$1"
    SRC_DIR="$2"
    
    CI_BUILD_OPTIONS="$3"
else
    usage; exit 1
fi
cd "$SRC_DIR"




# Check ci-ignore flag in commit message

commit_message=$(git log --pretty=%B -1)
if [[ "$commit_message" == *"[ci-ignore]"* ]]; then
    # Ignore this build
    echo "WARNING: [ci-ignore] detected, build aborted."
    exit 3
fi


# Choose between incremental build and full build

full_build=""
sha=$(git --git-dir="$SRC_DIR/.git" rev-parse HEAD)

if in-array "force-full-build" "$CI_BUILD_OPTIONS"; then
    full_build="Full build forced."
elif [ ! -e "$BUILD_DIR/CMakeCache.txt" ]; then
    full_build="No previous build detected."
elif [ ! -e "$BUILD_DIR/last-commit-built.txt" ]; then
    full_build="Last build's commit not found."
else
    # Sometimes, a change in a cmake script can cause an incremental
    # build to fail, so let's be extra cautious and make a full build
    # each time a .cmake file changes.
    last_commit_build="$(cat "$BUILD_DIR/last-commit-built.txt")"
    if git --git-dir="$SRC_DIR/.git" diff --name-only "$last_commit_build" "$sha" | grep 'cmake/.*\.cmake' ; then
        full_build="Detected changes in a CMake script file."
    fi
fi

if [ -n "$full_build" ]; then
    echo "Starting a full build. ($full_build)"
    # '|| true' is an ugly workaround, because rm sometimes fails to remove the
    # build directory on the Windows slaves, for reasons unknown yet.
    rm -rf "$BUILD_DIR" || true
    mkdir -p "$BUILD_DIR"
    # Flag. E.g. we check this before counting compiler warnings,
    # which is not relevant after an incremental build.
    touch "$BUILD_DIR/full-build"
    echo "$sha" > "$BUILD_DIR/last-commit-built.txt"
else
    rm -f "$BUILD_DIR/full-build"
    echo "Starting an incremental build"
fi
