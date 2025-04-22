#!/bin/bash
set -o errexit # Exit on error

usage() {
    echo "Usage: test.sh <build-dir> <src-dir> <script-dir> <node-name> <python-version>"
}

if [ "$#" -ge 4 ]; then
    BUILD_DIR="$(cd "$1" && pwd)"
    SRC_DIR="$(cd "$2" && pwd)"
    SCRIPT_DIR="$(cd "$3" && pwd)"
    NODE_NAME="$4"
    PYTHON_VERSION="$5"
else
    usage; exit 1
fi


echo "--------------- configure-and-build.sh vars ---------------"
echo "BUILD_DIR = $BUILD_DIR"
echo "SRC_DIR = $SRC_DIR"
echo "SCRIPT_DIR = $SCRIPT_DIR"
echo "NODE_NAME = $NODE_NAME"
echo "-----------------------------------------------"


# Setup variables for following calls
. ${SCRIPT_DIR}/utils.sh
CI_PYTHON3_VERSION=${PYTHON_VERSION} # Needed by load-vm-env, might need to run this inside the docker env

## Setup env variables
load-vm-env

# Setup PYTHONPATH
export PYTHONPATH=""
if [ -e "$VM_PYTHON3_PYTHONPATH" ]; then
    export PYTHONPATH="$(cd $VM_PYTHON3_PYTHONPATH && pwd):$PYTHONPATH"
fi
if [ -e "$BUILD_DIR/python3/site-packages" ]; then
    export PYTHONPATH="$BUILD_DIR/python3/site-packages:$PYTHONPATH"
fi
if vm-is-windows && [ -e "$VM_PYTHON3_EXECUTABLE" ]; then
    pythonroot="$(dirname $VM_PYTHON3_EXECUTABLE)"
    pythonroot="$(cd "$pythonroot" && pwd)"
    export PATH="$pythonroot:$pythonroot/DLLs:$pythonroot/Lib:$PATH_RESET"
fi

# Setup SOFA_ROOT
export SOFA_ROOT=$BUILD_DIR

############
# Unit tests
/bin/bash "$SCRIPT_DIR/unit-tests.sh" run unit "$BUILD_DIR" "$SRC_DIR" $VM_MAX_PARALLEL_TESTS
/bin/bash "$SCRIPT_DIR/unit-tests.sh" print-summary unit "$BUILD_DIR" "$SRC_DIR" $VM_MAX_PARALLEL_TESTS

tests_suites=$("$SCRIPT_DIR/unit-tests.sh" count-test-suites unit $BUILD_DIR $SRC_DIR)
tests_total=$("$SCRIPT_DIR/unit-tests.sh" count-tests unit $BUILD_DIR $SRC_DIR)
tests_disabled=$("$SCRIPT_DIR/unit-tests.sh" count-disabled unit $BUILD_DIR $SRC_DIR)
tests_failures=$("$SCRIPT_DIR/unit-tests.sh" count-failures unit $BUILD_DIR $SRC_DIR)
tests_errors=$("$SCRIPT_DIR/unit-tests.sh" count-errors unit $BUILD_DIR $SRC_DIR)
tests_duration=$("$SCRIPT_DIR/unit-tests.sh" count-durations unit $BUILD_DIR $SRC_DIR)
############


#############
# Scene tests
/bin/bash "$SCRIPT_DIR/scene-tests.sh" run "$BUILD_DIR" "$SRC_DIR" $VM_MAX_PARALLEL_TESTS
/bin/bash "$SCRIPT_DIR/scene-tests.sh" print-summary "$BUILD_DIR" "$SRC_DIR" $VM_MAX_PARALLEL_TESTS

scenes_total=$(/bin/bash $SCRIPT_DIR/scene-tests.sh count-tested-scenes $BUILD_DIR $SRC_DIR)
scenes_successes=$("$SCRIPT_DIR/scene-tests.sh" count-successes $BUILD_DIR $SRC_DIR)
scenes_errors=$("$SCRIPT_DIR/scene-tests.sh" count-errors $BUILD_DIR $SRC_DIR)
scenes_crashes=$("$SCRIPT_DIR/scene-tests.sh" count-crashes $BUILD_DIR $SRC_DIR)
scenes_duration=$("$SCRIPT_DIR/scene-tests.sh" count-durations $BUILD_DIR $SRC_DIR)

# Clamping warning and error files to avoid Jenkins overflow
/bin/bash "$SCRIPT_DIR/scene-tests.sh" clamp-warnings "$BUILD_DIR" "$SRC_DIR" 5000
/bin/bash "$SCRIPT_DIR/scene-tests.sh" clamp-errors "$BUILD_DIR" "$SRC_DIR" 5000
#############


##################
# Regression tests
/bin/bash "$SCRIPT_DIR/unit-tests.sh" run regression "$BUILD_DIR" "$SRC_DIR" $VM_MAX_PARALLEL_TESTS
/bin/bash "$SCRIPT_DIR/unit-tests.sh" print-summary regression "$BUILD_DIR" "$SRC_DIR" $VM_MAX_PARALLEL_TESTS

regressions_suites=$("$SCRIPT_DIR/unit-tests.sh" count-test-suites regression $BUILD_DIR $SRC_DIR )
regressions_total=$("$SCRIPT_DIR/unit-tests.sh" count-tests regression $BUILD_DIR $SRC_DIR )
regressions_disabled=$("$SCRIPT_DIR/unit-tests.sh" count-disabled regression $BUILD_DIR $SRC_DIR )
regressions_failures=$("$SCRIPT_DIR/unit-tests.sh" count-failures regression $BUILD_DIR $SRC_DIR )
regressions_errors=$("$SCRIPT_DIR/unit-tests.sh" count-errors regression $BUILD_DIR $SRC_DIR )
regressions_duration=$("$SCRIPT_DIR/unit-tests.sh" count-durations regression $BUILD_DIR $SRC_DIR )
##################

