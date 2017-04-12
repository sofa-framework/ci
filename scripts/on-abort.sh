#!/bin/bash
echo "------------- ON-ABORT SCRIPT -------------"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="$(cd "$1" && pwd)"
SRC_DIR="$(cd "$2" && pwd)"
COMPILER="$3"
ARCHITECTURE="$4"
BUILD_TYPE="$5"
BUILD_OPTIONS="${*:6}"

if [ ! -e "$BUILD_DIR/build-started" ]; then
    echo "Nothing to do."
    exit
fi

. "$SCRIPT_DIR"/dashboard.sh

# We need dashboard env vars in case of abort
dashboard-export-vars "$COMPILER" "$ARCHITECTURE" "$BUILD_TYPE" "$BUILD_OPTIONS"

dashboard-notify "status=aborted"