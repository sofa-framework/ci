#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/functions.sh

# This script basically runs 'make' and saves the compilation output
# in make-output.txt.

## Significant environnement variables:
# - CI_MAKE_OPTIONS       # additional arguments to pass to make
# - CI_ARCH               # x86|amd64  (32-bit or 64-bit build - Windows-specific)
# - CI_COMPILER           # important for Visual Studio (VS-2012, VS-2013 or VS-2015)

# Exit on error
set -o errexit


### Checks

usage() {
    echo "Usage: compile.sh <build-dir> <compiler> <architecture>"
}

if [[ "$#" = 3 ]]; then
    BUILD_DIR="$(cd "$1" && pwd)"
    CI_COMPILER="$2"
    CI_ARCH="$3"
else
    usage; exit 1
fi

if [[ ! -e "$BUILD_DIR/CMakeCache.txt" ]]; then
    echo "Error: '$BUILD_DIR' does not look like a build directory."
    usage; exit 1
fi



### Defaults

if [ -z "$CI_ARCH" ]; then CI_ARCH="x86"; fi


### Actual work

call-make() {
    if vm-is-windows; then
        # Call vcvarsall.bat first to setup environment
        if [ "$CI_COMPILER" = "VS-2015" ]; then
            vcvarsall="call \"%VS140COMNTOOLS%..\\..\\VC\vcvarsall.bat\" $CI_ARCH"
        elif [ "$CI_COMPILER" = "VS-2013" ]; then
            vcvarsall="call \"%VS120COMNTOOLS%..\\..\\VC\vcvarsall.bat\" $CI_ARCH"
        else
            vcvarsall="call \"%VS110COMNTOOLS%..\\..\\VC\vcvarsall.bat\" $CI_ARCH"
        fi
        toolname="nmake"
        if [ -x "$(command -v ninja)" ]; then
        	echo "Using ninja as build system"
            toolname="ninja"
        fi
        echo "Calling $COMSPEC /c \"$vcvarsall & $toolname $CI_MAKE_OPTIONS\""
        $COMSPEC /c "$vcvarsall & $toolname $CI_MAKE_OPTIONS"
    else
    	toolname="make"
        if [ -x "$(command -v ninja)" ]; then
            echo "Using ninja as build system"
	        toolname="ninja"
        fi 
	$toolname $CI_MAKE_OPTIONS
    fi
}

cd "$BUILD_DIR"

# The output of make is saved to a file, to check for warnings later. Since make
# is inside a pipe, errors will go undetected, thus we create a file
# 'make-failed' when make fails, to check for errors.
rm -f make-failed
( call-make 2>&1 || touch make-failed ) | tee make-output.txt

if [ -e make-failed ]; then
    exit 1
fi
