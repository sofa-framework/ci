#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="$(cd "$1" && pwd)"
SRC_DIR="$(cd "$2" && pwd)"
COMPILER="$3"
ARCHITECTURE="$4"
BUILD_TYPE="$5"
BUILD_OPTIONS="${*:6}"

on-success() {
    echo "on-success()"
}

on-unstable() {
    echo "on-unstable()"
}

on-failure() {
    echo "on-failure()"
}

on-error() {
    echo "on-error()"
}

on-abort() {
    echo "------------- ON-ABORT SCRIPT -------------"

    if [ ! -e "$BUILD_DIR/build-started" ]; then
        echo "Nothing to do."
        exit
    fi

    . "$SCRIPT_DIR"/dashboard.sh

    # We need dashboard env vars in case of abort
    dashboard-export-vars "$COMPILER" "$ARCHITECTURE" "$BUILD_TYPE" "$BUILD_OPTIONS"

    dashboard-notify "status=aborted"
}

local BUILD_RESULT="UNKNOWN"
if [ -e "$BUILD_DIR/build-result" ]; then
    BUILD_RESULT="$(cat $BUILD_DIR/build-result)"
fi
echo "BUILD_RESULT = $BUILD_RESULT"

case "$BUILD_RESULT" in
    SUCCESS) on-success;;
    UNSTABLE) on-unstable;;
    FAILURE) on-failure;;
    ERROR) on-error;;
    ABORT) on-abort;;
esac
