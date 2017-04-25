#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/utils.sh

# Here we pick what gets to be compiled. The role of this script is to
# call cmake with the appropriate options. After this, the build
# directory should be ready to run 'make'.

## Significant environnement variables:
# - CI_JOB                    (e.g. ubuntu_gcc-4.8_options)
# - CI_OPTIONS                if contains "options" then activate plugins
# - CI_CMAKE_OPTIONS          (additional arguments to pass to cmake)
# - ARCHITECTURE = x86 | amd64     (for Windows builds)
# - BUILD_TYPE             Debug|Release
# - CC and CXX
# - COMPILER               # important for Visual Studio paths (VS-2012, VS-2013 or VS-2015)


# Exit on error
set -o errexit


## Checks

usage() {
    echo "Usage: configure.sh <build-dir> <src-dir> <compiler> <architecture> <build-type> <build-options>"
}

if [ "$#" -eq 6 ]; then
    BUILD_DIR="$(cd "$1" && pwd)"
    if vm-is-windows; then
        # pwd with a Windows format (c:/ instead of /c/)
        SRC_DIR="$(cd "$2" && pwd -W)"
    else
        SRC_DIR="$(cd "$2" && pwd)"
    fi
    COMPILER="$3"
    ARCHITECTURE="$4"
    BUILD_TYPE="$5"
    BUILD_OPTIONS="$6"

    # sanitize vars
    BUILD_TYPE="${BUILD_TYPE^}"
else
    usage; exit 1
fi

if [[ ! -d "$SRC_DIR/applications/plugins" ]]; then
    echo "Error: '$SRC_DIR' does not look like a SOFA source tree."
    usage; exit 1
fi

cd "$SRC_DIR"


# Get Windows dependency pack

if vm-is-windows && [ ! -d "$SRC_DIR/lib" ]; then
    echo "Copying dependency pack in the source tree."
    curl "https://www.sofa-framework.org/download/WinDepPack/$COMPILER/latest" --output dependencies_tmp.zip
    unzip dependencies_tmp.zip -d dependencies_tmp
    cp -rf dependencies_tmp/*/* "$SRC_DIR"
    rm -rf dependencies_tmp*
fi


# Choose between incremental build and full build

full_build=""
sha=$(git --git-dir="$SRC_DIR/.git" rev-parse HEAD)

if in-array "force-full-build" "$BUILD_OPTIONS"; then
    full_build="Full build forced."
elif [ ! -e "$BUILD_DIR/CMakeCache.txt" ]; then
    full_build="No previous build detected."
elif [ ! -e "$BUILD_DIR/last-commit-built.txt" ]; then
    full_build="Last build's commit not found."
else
    # Sometimes, a change in a cmake script can cause an incremental
    # build to fail, so let's be extra cautious and make a full build
    # each time a .cmake file changes.
    last_commit_build="$(cat "$BUILD_DIR/last-commit-built.txt")"
    if git --git-dir="$SRC_DIR/.git" diff --name-only "$last_commit_build" "$sha" | grep 'cmake/.*\.cmake' ; then
        full_build="Detected changes in a CMake script file."
    fi
fi

if [ -n "$full_build" ]; then
    echo "Starting a full build. ($full_build)"
    # '|| true' is an ugly workaround, because rm sometimes fails to remove the
    # build directory on the Windows slaves, for reasons unknown yet.
    rm -rf "$BUILD_DIR" || true
    mkdir -p "$BUILD_DIR"
    # Flag. E.g. we check this before counting compiler warnings,
    # which is not relevant after an incremental build.
    touch "$BUILD_DIR/full-build"
    echo "$sha" > "$BUILD_DIR/last-commit-built.txt"
else
    rm -f "$BUILD_DIR/full-build"
    echo "Starting an incremental build"
fi



# CMake options

cmake_options="-DCMAKE_COLOR_MAKEFILE=OFF -DCMAKE_BUILD_TYPE=$BUILD_TYPE"

append() {
    cmake_options="$cmake_options $*"
}

# Cache systems
if vm-is-windows; then
    if [ -n "$VM_CLCACHE_PATH" ]; then
        append "-DCMAKE_C_COMPILER=$VM_CLCACHE_PATH/bin/clcache.bat"
        append "-DCMAKE_CXX_COMPILER=$VM_CLCACHE_PATH/bin/clcache.bat"
    fi
else
    if [ -x "$(command -v ccache)" ]; then
        export CC="ccache "
        export CXX="ccache "
    fi
fi

# Options common to all configurations
if [ -n "$VM_QT_PATH" ]; then
    if vm-is-windows; then
        qt_compiler=msvc"$(cut -d "-" -f 2 <<< "$COMPILER")"
    else
        qt_compiler="$(cut -d "-" -f 1 <<< "$COMPILER")"
    fi
    if [[ "$ARCHITECTURE" == "amd64" ]]; then
        append "-DQt5_DIR=$VM_QT_PATH/"$qt_compiler"_64/lib/cmake/Qt5"
    else
        append "-DQt5_DIR=$VM_QT_PATH/"$qt_compiler"/lib/cmake/Qt5"
    fi
fi
if [ -n "$VM_BOOST_PATH" ]; then
    append "-DBOOST_ROOT=$VM_BOOST_PATH"
    append "-DBOOST_LIBRARYDIR=$VM_BOOST_PATH/lib64-msvc-14.0"
fi
if [ -n "$VM_PYTHON_PATH" ]; then
    append "-DPYTHON_LIBRARY=$VM_PYTHON_PATH/libs/python27.lib"
    append "-DPYTHON_INCLUDE_DIR=$VM_PYTHON_PATH/include"
fi
append "-DPLUGIN_SOFAPYTHON=ON"
append "-DSOFA_BUILD_TUTORIALS=OFF"
append "-DSOFA_BUILD_TESTS=ON"

# "build-all-plugins" specific options
if in-array "build-all-plugins" "$BUILD_OPTIONS"; then
    # Build with as many options enabled as possible
    append "-DSOFA_BUILD_METIS=ON"
    append "-DSOFA_BUILD_ARTRACK=ON"
    append "-DSOFA_BUILD_MINIFLOWVR=ON"

    if [ -n "$VM_BULLET_PATH" ]; then
        append "-DBullet_DIR=$VM_BULLET_PATH"
    fi

    ### Plugins
    append "-DPLUGIN_ARTRACK=ON"
    if [ -n "$VM_BULLET_PATH" ]; then
        append "-DPLUGIN_BULLETCOLLISIONDETECTION=ON"
    else
        append "-DPLUGIN_BULLETCOLLISIONDETECTION=OFF"
    fi
    # Missing CGAL library
    append "-DPLUGIN_CGALPLUGIN=OFF"
    if [[ "$VM_HAS_ASSIMP" == "true" ]]; then
        append "-DPLUGIN_COLLADASCENELOADER=ON"
    else
        append "-DPLUGIN_COLLADASCENELOADER=OFF"
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
    if [[ "$VM_HAS_OPENCASCADE" == "true" ]]; then
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
    append "-DPLUGIN_SENSABLEEMULATION=ON"

    # Requires Sixense libraries.
    append "-DPLUGIN_SIXENSEHYDRA=OFF"
    append "-DPLUGIN_SOFACARVING=ON"
    if [[ "$VM_HAS_CUDA" == "true" ]]; then
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
if [ -n "$CI_CMAKE_OPTIONS" ]; then
    cmake_options="$cmake_options $CI_CMAKE_OPTIONS"
fi

cd "$BUILD_DIR"


# Configure

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
        if [[ "$COMPILER" == "VS-2015" ]]; then
            vcvarsall="call \"%VS140COMNTOOLS%\\..\\..\\VC\vcvarsall.bat\" $ARCHITECTURE"
        elif [[ "$COMPILER" == "VS-2013" ]]; then
            vcvarsall="call \"%VS120COMNTOOLS%\\..\\..\\VC\vcvarsall.bat\" $ARCHITECTURE"
        else
            vcvarsall="call \"%VS110COMNTOOLS%\\..\\..\\VC\vcvarsall.bat\" $ARCHITECTURE"
        fi
        echo "Calling $COMSPEC /c \"$vcvarsall & cmake $*\""
        $COMSPEC /c "$vcvarsall & cmake $*"
    else
        cmake "$@"
    fi
}

echo "Calling cmake with the following options:"
echo "$cmake_options" | tr -s ' ' '\n'
if [ -e "full-build" ]; then
    call-cmake -G"$(generator)" $cmake_options "$SRC_DIR"
else
    call-cmake $cmake_options .
fi
