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
    echo "Usage: compile.sh <build-dir> <config> <build-options>"
}

if [ "$#" -ge 2 ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    . "$SCRIPT_DIR"/utils.sh

    BUILD_DIR="$(cd "$1" && pwd)"
    CONFIG="$2"
    PLATFORM="$(get-platform-from-config "$CONFIG")"
    COMPILER="$(get-compiler-from-config "$CONFIG")"
    ARCHITECTURE="$(get-architecture-from-config "$CONFIG")"
    BUILD_OPTIONS="${*:3}"
    if [ -z "$BUILD_OPTIONS" ]; then
        BUILD_OPTIONS="$(get-build-options)" # use env vars (Jenkins)
    fi
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

# The output of make is saved to a file, to check for warnings later. Since make
# is inside a pipe, errors will go undetected, thus we create a file
# 'make-failed' when make fails, to check for errors.
rm -f "$BUILD_DIR/make-failed"

( call-make "$BUILD_DIR" "all" 2>&1 || touch "$BUILD_DIR/make-failed" ) | tee "$BUILD_DIR/make-output.txt"
if in-array "build-release-package" "$BUILD_OPTIONS"; then
    echo "-------------- Start packaging --------------" | tee -a "$BUILD_DIR/make-output.txt"
    ( call-make "$BUILD_DIR" "package" 2>&1 || touch "$BUILD_DIR/make-failed" ) | tee -a "$BUILD_DIR/make-output.txt"
    if vm-is-macos; then
        # Rerun CMake and CPack in Bundle mode
        echo "--- [MacOS] Rerunning with SOFA_BUILD_APP_BUNDLE=ON ---"
        call-cmake "$BUILD_DIR" "-DCPACK_BINARY_ZIP=OFF" "-DCPACK_GENERATOR=DragNDrop" "-DCPACK_BINARY_DRAGNDROP=ON" "-DSOFA_BUILD_APP_BUNDLE=ON" .
        ( call-make "$BUILD_DIR" "package" 2>&1 || touch "$BUILD_DIR/make-failed" ) | tee -a "$BUILD_DIR/make-output.txt"
    fi
    echo "---------------------------------------------" | tee -a "$BUILD_DIR/make-output.txt"
fi

if [ -e "$BUILD_DIR/make-failed" ]; then
    exit 1
fi
