#!/bin/bash

usage() {
    echo "Usage: post-build.sh <build-dir> <compiler> <architecture> <build-type> <build-options>"
}

if [ "$#" -ge 4 ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    . "$SCRIPT_DIR"/utils.sh

    BUILD_DIR="$(cd "$1" && pwd)"
    COMPILER="$2"
    ARCHITECTURE="$3"
    BUILD_TYPE="$4"
    BUILD_OPTIONS="${*:5}"
    if [ -z "$BUILD_OPTIONS" ]; then
        BUILD_OPTIONS="$(import-build-options)" # use env vars (Jenkins)
    fi
else
    usage; exit 1
fi

. "$SCRIPT_DIR"/dashboard.sh
. "$SCRIPT_DIR"/github.sh

dashboard-export-vars "$COMPILER" "$ARCHITECTURE" "$BUILD_TYPE" "$BUILD_OPTIONS"
github-export-vars "$BUILD_OPTIONS"


on-failure() {
    dashboard-notify "status=fail"
    github-notify "failure" "FAILURE"
}

on-error() {
    dashboard-notify "status=fail"
    github-notify "error" "ERROR"
}

on-aborted() {
    dashboard-notify "status=cancel"
    github-notify "failure" "ABORTED"
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
