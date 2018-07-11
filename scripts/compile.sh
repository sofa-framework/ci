#!/bin/bash
set -o errexit # Exit on error

# This script basically runs 'make' and saves the compilation output
# in make-output.txt.

## Significant environnement variables:
# - VM_MAKE_OPTIONS       # additional arguments to pass to make
# - ARCHITECTURE               # x86|amd64  (32-bit or 64-bit build - Windows-specific)
# - COMPILER           # important for Visual Studio (vs-2012, vs-2013 or vs-2015)


### Checks

usage() {
    echo "Usage: compile.sh <build-dir> <config>"
}

if [ "$#" -eq 2 ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    . "$SCRIPT_DIR"/utils.sh

    BUILD_DIR="$(cd "$1" && pwd)"
    CONFIG="$2"
    PLATFORM="$(get-platform-from-config "$CONFIG")"
    COMPILER="$(get-compiler-from-config "$CONFIG")"
    ARCHITECTURE="$(get-architecture-from-config "$CONFIG")"
else
    usage; exit 1
fi

if [[ ! -e "$BUILD_DIR/CMakeCache.txt" ]]; then
    echo "Error: '$BUILD_DIR' does not look like a build directory."
    usage; exit 1
fi

echo "--------------- compile.sh vars ---------------"
echo "BUILD_DIR = $BUILD_DIR"
echo "CONFIG = $CONFIG"
echo "PLATFORM = $PLATFORM"
echo "COMPILER = $COMPILER"
echo "ARCHITECTURE = $ARCHITECTURE"
echo "-----------------------------------------------"

call-make() {
    build_dir="$(cd "$1" && pwd)"
    shift # Remove first arg
    
    if vm-is-windows; then
        msvc_comntools="$(get-msvc-comntools $COMPILER)"
        # Call vcvarsall.bat first to setup environment
        vcvarsall="call \"%${msvc_comntools}%\\..\\..\\VC\vcvarsall.bat\" $ARCHITECTURE"
        toolname="nmake" # default
        if [ -x "$(command -v ninja)" ]; then
        	echo "Using ninja as build system"
            toolname="ninja"
        fi
        build_dir_windows="$(cd "$build_dir" && pwd -W | sed 's#/#\\#g')"
        if [ -n "$EXECUTOR_LINK_WINDOWS_BUILD" ]; then
            build_dir_windows="$EXECUTOR_LINK_WINDOWS_BUILD"
        fi
        echo "Calling: $COMSPEC /c \"$vcvarsall & cd $build_dir_windows & $toolname $VM_MAKE_OPTIONS\""
        $COMSPEC /c "$vcvarsall & cd $build_dir_windows & $toolname $VM_MAKE_OPTIONS"
    else
    	toolname="make" # default
        if [ -x "$(command -v ninja)" ]; then
            echo "Using ninja as build system"
	        toolname="ninja"
        fi
        echo "Calling: $toolname $VM_MAKE_OPTIONS"
        cd $build_dir && $toolname $VM_MAKE_OPTIONS
    fi
}

# The output of make is saved to a file, to check for warnings later. Since make
# is inside a pipe, errors will go undetected, thus we create a file
# 'make-failed' when make fails, to check for errors.
rm -f "$BUILD_DIR/make-failed"
( call-make "$BUILD_DIR" 2>&1 || touch "$BUILD_DIR/make-failed" ) | tee "$BUILD_DIR/make-output.txt"

if [ -e "$BUILD_DIR/make-failed" ]; then
    exit 1
fi
