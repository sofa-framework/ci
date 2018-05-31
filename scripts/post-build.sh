#!/bin/bash
set -o errexit # Exit on error

usage() {
    echo "Usage: post-build.sh <build-dir> <platform> <compiler> <architecture> <build-type> <build-options>"
}

if [ "$#" -ge 4 ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    . "$SCRIPT_DIR"/utils.sh

    BUILD_DIR="$(cd "$1" && pwd)"
    PLATFORM="$2"
    COMPILER="$3"
    ARCHITECTURE="$4"
    BUILD_TYPE="$5"
    BUILD_OPTIONS="${*:6}"
    if [ -z "$BUILD_OPTIONS" ]; then
        BUILD_OPTIONS="$(get-build-options)" # use env vars (Jenkins)
    fi
elif [ -n "$BUILD_ID" ]; then # script called by Jenkins build
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    . "$SCRIPT_DIR"/utils.sh
    
    BUILD_DIR="$WORKSPACE/../builds/${CI_COMPILER}_${CI_PLUGINS}_${CI_TYPE}_${CI_ARCH}"
    PLATFORM="${CI_COMPILER%_*}"
    COMPILER="${CI_COMPILER#*_}"
    ARCHITECTURE="$CI_ARCH"
    BUILD_TYPE="$CI_TYPE"
    BUILD_OPTIONS="$(get-build-options)" # use env vars (Jenkins)
else
    usage; exit 1
fi

. "$SCRIPT_DIR"/dashboard.sh
. "$SCRIPT_DIR"/github.sh

github-export-vars "$PLATFORM" "$COMPILER" "$ARCHITECTURE" "$BUILD_TYPE" "$BUILD_OPTIONS"
dashboard-export-vars "$PLATFORM" "$COMPILER" "$ARCHITECTURE" "$BUILD_TYPE" "$BUILD_OPTIONS"


on-failure() {
    dashboard-notify "status=fail"
    github-notify "failure" "Build failed."
}

on-error() {
    dashboard-notify "status=fail"
    github-notify "error" "Unexpected error, see log for details."
}

on-aborted() {
    dashboard-notify "status=cancel"
    github-notify "failure" "Build canceled."
}

# Get build result from Groovy script output (Jenkins)
BUILD_RESULT="UNKNOWN"
if [ -e "$BUILD_DIR/build-result" ]; then
    BUILD_RESULT="$(cat $BUILD_DIR/build-result)"
fi
echo "BUILD_RESULT = $BUILD_RESULT"

case "$BUILD_RESULT" in
    FAILURE) on-failure;;
    ERROR) on-error;;
    ABORTED) on-aborted;;
esac


# Jenkins: remove shortcut for Windows jobs (too long path problem)
if vm-is-windows && [ -n "$BUILD_ID" ] && [ -n "$CI_PLUGINS" ] && [ -n "$CI_TYPE" ] && [ -n "$CI_ARCH" ]; then
    cmd //c "rmdir j:\%BUILD_ID%-%CI_PLUGINS%_%CI_TYPE%_%CI_ARCH%"
fi

