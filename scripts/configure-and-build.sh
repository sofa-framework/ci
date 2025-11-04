#!/bin/bash
set -o errexit # Exit on error

usage() {
    echo "Usage: configure-and-build.sh <build-dir> <src-dir> <script-dir> <log-dir> <node-name> <build-type> <config> <python-version> <preset> <generate-binaries> <ci-depends-on-flags>"
}

if [ "$#" -ge 11 ]; then
    BUILD_DIR="$(cd "$1" && pwd)"
    SRC_DIR="$(cd "$2" && pwd)"
    SCRIPT_DIR="$(cd "$3" && pwd)"
    LOG_DIR="$(cd "$4" && pwd)"
    NODE_NAME="$5"
    BUILD_TYPE="$6"
    CONFIG="$7"
    PYTHON_VERSION="$8"
    PRESET="$9"
    GENERATE_BINARIES="${10}"
    CI_DEPENDS_ON_FLAGS="${11}"
else
    usage; exit 1
fi


echo "--------------- configure-and-build.sh vars ---------------"
echo "BUILD_DIR = $BUILD_DIR"
echo "SRC_DIR = $SRC_DIR"
echo "SCRIPT_DIR = $SCRIPT_DIR"
echo "NODE_NAME = $NODE_NAME"
echo "BUILD_TYPE = $BUILD_TYPE"
echo "CONFIG = $CONFIG"
echo "PYTHON_VERSION = $PYTHON_VERSION"
echo "PRESET = $PRESET"
echo "GENERATE_BINARIES = $GENERATE_BINARIES"
echo "CI_DEPENDS_ON_FLAGS = $CI_DEPENDS_ON_FLAGS"
echo "-----------------------------------------------"


# Setup variables for following calls

. ${SCRIPT_DIR}/utils.sh
CI_PYTHON3_VERSION=${PYTHON_VERSION} # Needed by load-vm-env, might need to run this inside the docker env

## Setup env variables
load-vm-env

if [[ "${PRESET}" == *"-dev" ]]; then
    BUILD_OPTIONS="activate-tests build-scope-$( echo "${PRESET}" | awk -F'-' '{print $1}' )"
else
    BUILD_OPTIONS="build-scope-${PRESET}"
fi


if [ "${GENERATE_BINARIES}" == "true" ]; then
    BUILD_OPTIONS="$BUILD_OPTIONS build-release-package"
fi

. ${SCRIPT_DIR}/configure.sh "$BUILD_DIR" "$SRC_DIR" "$LOG_DIR" "$CONFIG" "$CI_DEPENDS_ON_FLAGS" "$BUILD_TYPE" "$BUILD_OPTIONS" 

## Call to build 
. ${SCRIPT_DIR}/compile.sh "$BUILD_DIR" "$LOG_DIR" "$CONFIG" "$BUILD_OPTIONS"
