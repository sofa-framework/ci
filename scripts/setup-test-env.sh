#!/bin/bash

usage() {
    echo "Usage: setup-test-env.sh <build-dir> <script-dir> <node-name> <python-version>"
}

if [ "$#" -eq 4 ]; then
    BUILD_DIR="$(cd "$1" && pwd)"
    SCRIPT_DIR="$(cd "$2" && pwd)"
    NODE_NAME="$3"
    PYTHON_VERSION="$4"
else
    usage; exit 1;
fi


echo "--------------- configure-and-build.sh vars ---------------"
echo "BUILD_DIR = $BUILD_DIR"
echo "SCRIPT_DIR = $SCRIPT_DIR"
echo "NODE_NAME = $NODE_NAME"
echo "PYTHON_VERSION = $PYTHON_VERSION"
echo "-----------------------------------------------"


# Setup variables for following calls
. ${SCRIPT_DIR}/utils.sh
CI_PYTHON3_VERSION=${PYTHON_VERSION} # Needed by load-vm-env, might need to run this inside the docker env

## Setup env variables
load-vm-env

_prepend_pythonpath() {
    local dir
    dir="$(cd "$1" 2>/dev/null && { vm-is-windows && pwd -W || pwd; })" || return 0
    local sep=":"
    vm-is-windows && sep=";"
    export PYTHONPATH="$dir${PYTHONPATH:+$sep$PYTHONPATH}"
}

export PYTHONPATH=""
[ -e "$VM_PYTHON3_PYTHONPATH" ] && _prepend_pythonpath "$VM_PYTHON3_PYTHONPATH"
[ -e "$BUILD_DIR/lib/python3/site-packages" ] && _prepend_pythonpath "$BUILD_DIR/lib/python3/site-packages"


if vm-is-windows && [ -e "$VM_PYTHON3_EXECUTABLE" ]; then
    pythonroot="$(dirname $VM_PYTHON3_EXECUTABLE)"
    pythonroot="$(cd "$pythonroot" && pwd)"
    export PATH="$pythonroot:$pythonroot/DLLs:$pythonroot/Lib:$PATH"
fi


# Remove SofaCUDA, and MeshSTEPLoader from plugin_list.conf.default
echo "Removing SofaCUDA and SofaPython from plugin_list.conf.default"
if vm-is-windows; then
    plugin_conf="$BUILD_DIR/bin/plugin_list.conf.default"
else
    plugin_conf="$BUILD_DIR/lib/plugin_list.conf.default"
fi
grep -v "CUDA" "$plugin_conf" > "${plugin_conf}.tmp" && mv "${plugin_conf}.tmp" "$plugin_conf"
grep -v "MeshSTEPLoader " "$plugin_conf" > "${plugin_conf}.tmp" && mv "${plugin_conf}.tmp" "$plugin_conf"


# Setup SOFA_ROOT
export SOFA_ROOT=$BUILD_DIR

export RESULTS_DIR=$BUILD_DIR/tests_results
if [[ ! -d "$RESULTS_DIR" ]]; then
    mkdir -p "$RESULTS_DIR"
fi
