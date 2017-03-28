#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/functions.sh

# Here we pick what gets to be compiled. The role of this script is to
# call cmake with the appropriate options. After this, the build
# directory should be ready to run 'make'.

## Significant environnement variables:
# - CI_JOB                    (e.g. ubuntu_gcc-4.8_options)
# - CI_OPTIONS                if contains "options" then activate plugins
# - CI_CMAKE_OPTIONS          (additional arguments to pass to cmake)
# - CI_ARCH = x86 | amd64     (for Windows builds)
# - CI_BUILD_TYPE             Debug|Release
# - CC and CXX
# - CI_COMPILER               # important for Visual Studio paths (VS-2012, VS-2013 or VS-2015)


# Exit on error
set -o errexit


## Checks

usage() {
    echo "Usage: configure.sh <build-dir> <src-dir> <compiler> <architecture> <build-type> <build-options>"
}

if [[ "$#" = 6 ]]; then
    BUILD_DIR="$(cd "$1" && pwd)"
    SRC_DIR="$(cd "$2" && pwd)"
    # if vm-is-windows; then
        # # pwd with a Windows format (c:/ instead of /c/)
        # SRC_DIR="$(cd "$2" && pwd -W)"
    # else
        # SRC_DIR="$(cd "$2" && pwd)"
    # fi
    CI_COMPILER="$3"
    CI_ARCH="$4"
    CI_BUILD_TYPE="$5"
    CI_BUILD_OPTIONS="$6"
else
    usage; exit 1
fi

if [[ ! -d "$SRC_DIR/applications/plugins" ]]; then
    echo "Error: '$SRC_DIR' does not look like a Sofa source tree."
    usage; exit 1
fi



## Defaults

if [ -z "$CI_ARCH" ]; then CI_ARCH="x86"; fi
if [ -z "$CI_JOB" ]; then CI_JOB="$JOB_NAME"; fi
if [ -z "$CI_JOB" ]; then CI_JOB="default"; fi
if [ -z "$CI_BUILD_TYPE" ]; then CI_BUILD_TYPE="Release"; fi


## Utils

generator() {
    if [ -x "$(command -v ninja)" ]; then
        echo "Ninja"
    elif vm-is-windows; then
        echo "\"NMake Makefiles\""
    else
        echo "Unix Makefiles"
    fi
}

call-cmake() {
    if vm-is-windows; then
        # Call vcvarsall.bat first to setup environment
        if [ "$CI_COMPILER" = "VS-2015" ]; then
            vcvarsall="call \"%VS140COMNTOOLS%..\\..\\VC\vcvarsall.bat\" $CI_ARCH"
        elif [ "$CI_COMPILER" = "VS-2013" ]; then
            vcvarsall="call \"%VS120COMNTOOLS%..\\..\\VC\vcvarsall.bat\" $CI_ARCH"
        else
            vcvarsall="call \"%VS110COMNTOOLS%..\\..\\VC\vcvarsall.bat\" $CI_ARCH"
        fi
        echo "Calling $COMSPEC /c \"$vcvarsall & cmake $*\""
        $COMSPEC /c "$vcvarsall & cmake $*"
    else
        cmake "$@"
    fi
}


## CMake options

cmake_options="-DCMAKE_COLOR_MAKEFILE=OFF -DCMAKE_BUILD_TYPE=$CI_BUILD_TYPE"

append() {
    cmake_options="$cmake_options $*"
}

# Options common to all configurations
append "-DSOFA_BUILD_TUTORIALS=ON"
append "-DSOFA_BUILD_TESTS=ON"
append "-DPLUGIN_SOFAPYTHON=ON"
if [[ -n "$CI_HAVE_BOOST" ]]; then
    append "-DBOOST_ROOT=$CI_BOOST_PATH"
fi

if in-array "build-all-plugins" "$CI_BUILD_OPTIONS"; then
    # Build with as many options enabled as possible
    append "-DSOFA_BUILD_METIS=ON"
    append "-DSOFA_BUILD_ARTRACK=ON"
    append "-DSOFA_BUILD_MINIFLOWVR=ON"

    if [[ -n "$CI_QT_PATH" ]]; then
        append "-DQT_ROOT=$CI_QT_PATH"
    fi

    if [[ -n "$CI_BULLET_DIR" ]]; then
        append "-DBullet_DIR=$CI_BULLET_DIR"
    fi

    ### Plugins
    append "-DPLUGIN_ARTRACK=ON"
    if [[ -n "$CI_BULLET_DIR" ]]; then
        append "-DPLUGIN_BULLETCOLLISIONDETECTION=ON"
    else
        append "-DPLUGIN_BULLETCOLLISIONDETECTION=OFF"
    fi
    # Missing CGAL library
    append "-DPLUGIN_CGALPLUGIN=OFF"
    # For Windows, there is the dll of the assimp library *inside* the repository
    if [[ ( $(uname) = Darwin || $(uname) = Linux ) && -z "$CI_HAVE_ASSIMP" ]]; then
        append "-DPLUGIN_COLLADASCENELOADER=OFF"
    else
        append "-DPLUGIN_COLLADASCENELOADER=ON"
    fi
    append "-DPLUGIN_COMPLIANT=ON"
    append "-DPLUGIN_EXTERNALBEHAVIORMODEL=ON"
    append "-DPLUGIN_FLEXIBLE=ON"
    # Requires specific libraries.
    append "-DPLUGIN_HAPTION=OFF"
    append "-DPLUGIN_IMAGE=ON"
    append "-DPLUGIN_INVERTIBLEFVM=ON"
    append "-DPLUGIN_MANIFOLDTOPOLOGIES=ON"
    append "-DPLUGIN_MANUALMAPPING=ON"
    if [ -n "$CI_HAVE_OPENCASCADE" ]; then
        append "-DPLUGIN_MESHSTEPLOADER=ON"
    else
        append "-DPLUGIN_MESHSTEPLOADER=OFF"
    fi
    append "-DPLUGIN_MULTITHREADING=ON"
    append "-DPLUGIN_OPTITRACKNATNET=ON"
    # Does not compile, but it just needs to be updated.
    append "-DPLUGIN_PERSISTENTCONTACT=OFF"
    append "-DPLUGIN_PLUGINEXAMPLE=ON"
    append "-DPLUGIN_REGISTRATION=ON"
    # Requires OpenHaptics libraries.
    append "-DPLUGIN_SENSABLE=OFF"
    if [[ -n "$CI_HAVE_BOOST" ]]; then
        append "-DPLUGIN_SENSABLEEMULATION=ON"
    else
        append "-DPLUGIN_SENSABLEEMULATION=OFF"
    fi
    # Requires Sixense libraries.
    append "-DPLUGIN_SIXENSEHYDRA=OFF"
    append "-DPLUGIN_SOFACARVING=ON"
    if [[ -n "$CI_HAVE_CUDA" ]]; then
        append "-DPLUGIN_SOFACUDA=ON"
    else
        append "-DPLUGIN_SOFACUDA=OFF"
    fi
    # Requires HAPI libraries.
    append "-DPLUGIN_SOFAHAPI=OFF"
    # Not sure if worth maintaining
    append "-DPLUGIN_SOFASIMPLEGUI=ON"
    append "-DPLUGIN_THMPGSPATIALHASHING=ON"
    # Requires XiRobot library.
    append "-DPLUGIN_XITACT=OFF"
    append "-DPLUGIN_RIGIDSCALE=ON"
fi

# Options passed via the environnement
if [ ! -z "$CI_CMAKE_OPTIONS" ]; then
    cmake_options="$cmake_options $CI_CMAKE_OPTIONS"
fi

cd "$BUILD_DIR"

## Configure

echo "Calling cmake with the following options:"
echo "$cmake_options" | tr -s ' ' '\n'
if [ -e "full-build" ]; then
    call-cmake -G"$(generator)" $cmake_options "$SRC_DIR"
else
    call-cmake $cmake_options .
fi
