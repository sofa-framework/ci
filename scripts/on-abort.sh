#!/bin/bash -ex
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/dashboard.sh

COMPILER="$1"
ARCHITECTURE="$2"
BUILD_TYPE="$3"
BUILD_OPTIONS="${*:4}"

# We need dashboard env vars in case of abort
dashboard-export-vars "$COMPILER" "$ARCHITECTURE" "$BUILD_TYPE" "$BUILD_OPTIONS"

echo "--------- ABORT TRAPPED ---------"
dashboard-notify "status=aborted"