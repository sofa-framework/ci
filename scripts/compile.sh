#!/bin/bash
set -o errexit # Exit on error
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/utils.sh

# This script basically runs 'make' and saves the compilation output
# in make-output.txt.

## Significant environnement variables:
# - VM_MAKE_OPTIONS       # additional arguments to pass to make
# - ARCHITECTURE               # x86|amd64  (32-bit or 64-bit build - Windows-specific)
# - COMPILER           # important for Visual Studio (VS-2012, VS-2013 or VS-2015)

# Exit on error
set -o errexit


### Checks

usage() {
    echo "Usage: compile.sh <build-dir> <compiler> <architecture>"
}

if [ "$#" -eq 3 ]; then
    BUILD_DIR="$(cd "$1" && pwd)"
    COMPILER="$2"
    ARCHITECTURE="$3"
else
    usage; exit 1
fi

if [[ ! -e "$BUILD_DIR/CMakeCache.txt" ]]; then
    echo "Error: '$BUILD_DIR' does not look like a build directory."
    usage; exit 1
fi

cd "$BUILD_DIR"


call-make() {
    if vm-is-windows; then
        # Call vcvarsall.bat first to setup environment
        if [[ "$COMPILER" == "VS-2015" ]]; then
            vcvarsall="call \"%VS140COMNTOOLS%\\..\\..\\VC\vcvarsall.bat\" $ARCHITECTURE"
        elif [[ "$COMPILER" == "VS-2013" ]]; then
            vcvarsall="call \"%VS120COMNTOOLS%\\..\\..\\VC\vcvarsall.bat\" $ARCHITECTURE"
        else
            vcvarsall="call \"%VS110COMNTOOLS%\\..\\..\\VC\vcvarsall.bat\" $ARCHITECTURE"
        fi
        toolname="nmake"
        if [ -x "$(command -v ninja)" ]; then
        	echo "Using ninja as build system"
            toolname="ninja"
        fi
        echo "Calling $COMSPEC /c \"$vcvarsall & $toolname $VM_MAKE_OPTIONS\""
        $COMSPEC /c "$vcvarsall & $toolname $VM_MAKE_OPTIONS"
    else
    	toolname="make"
        if [ -x "$(command -v ninja)" ]; then
            echo "Using ninja as build system"
	        toolname="ninja"
        fi 
        $toolname $VM_MAKE_OPTIONS
    fi
}

# The output of make is saved to a file, to check for warnings later. Since make
# is inside a pipe, errors will go undetected, thus we create a file
# 'make-failed' when make fails, to check for errors.
rm -f make-failed
( call-make 2>&1 || touch make-failed ) | tee make-output.txt

if [ -e make-failed ]; then
    exit 1
fi
