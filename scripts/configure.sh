#!/bin/bash
set -o errexit # Exit on error

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
# - COMPILER               # important for Visual Studio paths (vs-2012, vs-2013 or vs-2015)


## Checks

usage() {
    echo "Usage: configure.sh <build-dir> <src-dir> <config> <build-type> <build-options>"
}

if [ "$#" -ge 4 ]; then
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    . "$SCRIPT_DIR"/utils.sh

    BUILD_DIR="$(cd "$1" && pwd)"
    if vm-is-windows; then
        # pwd with a Windows format (c:/ instead of /c/)
        SRC_DIR="$(cd "$2" && pwd -W)"
    else
        SRC_DIR="$(cd "$2" && pwd)"
    fi
    CONFIG="$3"
    PLATFORM="$(get-platform-from-config "$CONFIG")"
    COMPILER="$(get-compiler-from-config "$CONFIG")"
    ARCHITECTURE="$(get-architecture-from-config "$CONFIG")"
    BUILD_TYPE="$4"
    BUILD_OPTIONS="${*:5}"
    if [ -z "$BUILD_OPTIONS" ]; then
        BUILD_OPTIONS="$(get-build-options)" # use env vars (Jenkins)
    fi
else
    usage; exit 1
fi

if [[ ! -d "$SRC_DIR/applications/plugins" ]]; then
    echo "Error: '$SRC_DIR' does not look like a SOFA source tree."
    usage; exit 1
fi

cd "$SRC_DIR"

echo "--------------- configure.sh vars ---------------"
echo "BUILD_DIR = $BUILD_DIR"
echo "SRC_DIR = $SRC_DIR"
echo "CONFIG = $CONFIG"
echo "PLATFORM = $PLATFORM"
echo "COMPILER = $COMPILER"
echo "ARCHITECTURE = $ARCHITECTURE"
echo "BUILD_TYPE = $BUILD_TYPE"
echo "BUILD_OPTIONS = $BUILD_OPTIONS"
echo "-------------------------------------------------"



########
# Init #
########

# Get Windows dependency pack
if vm-is-windows && [ ! -d "$SRC_DIR/lib" ]; then
    echo "Copying dependency pack in the source tree."
    curl -L "https://www.sofa-framework.org/download/WinDepPack/$COMPILER/latest" --output dependencies_tmp.zip
    unzip dependencies_tmp.zip -d dependencies_tmp > /dev/null
    cp -rf dependencies_tmp/*/* "$SRC_DIR"
    rm -rf dependencies_tmp*
fi

# Choose between incremental build and full build
full_build=""
if in-array "force-full-build" "$BUILD_OPTIONS"; then
    full_build="Full build forced."
elif [ ! -e "$BUILD_DIR/CMakeCache.txt" ]; then
    full_build="No previous build detected."
fi

if [ -n "$full_build" ]; then
    echo "Starting a full build. ($full_build)"
else
    echo "Starting an incremental build"
fi



#################
# CMake options #
#################

cmake_options=""
add-cmake-option() {
    cmake_options="$cmake_options $*"
}

# Compiler and cache
if vm-is-windows; then
    # Compiler
    # see comntools usage in call-cmake() for compiler selection on Windows

    # Cache
    if [ -x "$(command -v clcache)" ]; then
        export CLCACHE_DIR="J:/clcache"
        export CLCACHE_BASEDIR="$(cd "$BUILD_DIR" && pwd -W)"
        #export CLCACHE_HARDLINK=1 # this may cause cache corruption. see https://github.com/frerich/clcache/issues/282
        export CLCACHE_OBJECT_CACHE_TIMEOUT_MS=3600000
        clcache -M 17179869184 # Set cache size to 1024*1024*1024*16 = 16 GB
        
        add-cmake-option "-DCMAKE_C_COMPILER=clcache"
        add-cmake-option "-DCMAKE_CXX_COMPILER=clcache"
    fi
else
    # Compiler
    case "$COMPILER" in
        gcc*)
            c_compiler="gcc"
            cxx_compiler="g++"
            add-cmake-option "-DCMAKE_CXX_FLAGS=-fdiagnostics-color=always" # Colored output
        ;;
        clang*)
            c_compiler="clang"
            cxx_compiler="clang++"
            add-cmake-option "-DCMAKE_CXX_FLAGS=-fcolor-diagnostics" # Colored output
        ;;
        *) # other
            echo "Unknown compiler: $COMPILER"
            echo "Try a lucky guess..."
            c_compiler="$COMPILER"
            cxx_compiler="${COMPILER}++"
        ;;
    esac
    export CC="$c_compiler" # needed by CUDA
    export CXX="$cxx_compiler" # needed by CUDA
    add-cmake-option "-DCMAKE_C_COMPILER=$c_compiler"
    add-cmake-option "-DCMAKE_CXX_COMPILER=$cxx_compiler"

    # Cache
    if [ -x "$(command -v ccache)" ]; then
        export CCACHE_BASEDIR="$(cd "$BUILD_DIR" && pwd)"
        export CCACHE_MAXSIZE="12G"
        # export PATH="/usr/lib/ccache:$PATH" # /usr/lib/ccache contains symlinks for every compiler
        export CC="ccache $c_compiler -Qunused-arguments -Wno-deprecated-declarations"
        export CXX="ccache $cxx_compiler -Qunused-arguments -Wno-deprecated-declarations"
    fi
fi

# Options common to all configurations
add-cmake-option "-DCMAKE_BUILD_TYPE=$(tr '[:lower:]' '[:upper:]' <<< ${BUILD_TYPE:0:1})${BUILD_TYPE:1}"
add-cmake-option "-DSOFA_WITH_DEPRECATED_COMPONENTS=ON"
add-cmake-option "-DAPPLICATION_GETDEPRECATEDCOMPONENTS=ON"
add-cmake-option "-DSOFA_BUILD_TUTORIALS=ON"
add-cmake-option "-DSOFA_BUILD_TESTS=ON"
add-cmake-option "-DSOFAGUI_BUILD_TESTS=OFF"
add-cmake-option "-DPLUGIN_SOFAPYTHON=ON"
add-cmake-option "-DAPPLICATION_SOFAPHYSICSAPI=ON"

# Handle custom lib dirs
if vm-is-windows; then
    add-cmake-option "-DAPPLICATION_MODELER=OFF" # waiting to fix path length problem

    msvc_year="$(get-msvc-year $COMPILER)"
    msvc_version="$(get-compiler-version $COMPILER)"
    qt_compiler="msvc${msvc_year}"
else
    qt_compiler="${COMPILER%-*}" # gcc-4.8 -> gcc
fi
if [[ "$ARCHITECTURE" == "amd64" ]]; then
    qt_compiler="${qt_compiler}_64"
fi
if [[ "$VM_HAS_REQUIRED_LIBS" != "true" ]]; then
    echo "ERROR: VM_HAS_REQUIRED_LIBS is not true. Please make sure to have all required libs installed."
    exit 1
fi
if [ -d "$VM_QT_PATH" ]; then
    add-cmake-option "-DCMAKE_PREFIX_PATH=$VM_QT_PATH/${qt_compiler}"
fi
if vm-is-windows; then # Finding libs on Windows
    if [ -d "$VM_BOOST_PATH" ]; then
        add-cmake-option "-DBOOST_ROOT=$VM_BOOST_PATH"
    fi
    if [ -d "$VM_PYTHON_PATH" ]; then
        if [[ "$ARCHITECTURE" == "x86" ]]; then
            export VM_PYTHON_PATH="${VM_PYTHON_PATH}_x86"
        fi
        add-cmake-option "-DPYTHON_LIBRARY=$VM_PYTHON_PATH/libs/python27.lib"
        add-cmake-option "-DPYTHON_INCLUDE_DIR=$VM_PYTHON_PATH/include"
    fi
fi

# "build-all-plugins" specific options
if in-array "build-all-plugins" "$BUILD_OPTIONS"; then
    # Build with as many options enabled as possible
    add-cmake-option "-DSOFA_BUILD_METIS=ON"
    add-cmake-option "-DSOFA_BUILD_ARTRACK=ON"
    add-cmake-option "-DSOFA_BUILD_MINIFLOWVR=ON"
    
    # HeadlessRecorder is Linux only for now
    if [[ "$(uname)" == "Linux" ]]; then
        id=$(cat /etc/*-release | grep "ID")
        if [[ $id = *"centos"* ]]; then
            add-cmake-option "-DSOFAGUI_HEADLESS_RECORDER=OFF"
        else
            add-cmake-option "-DSOFAGUI_HEADLESS_RECORDER=ON"
        fi
    fi

    ### Plugins
    add-cmake-option "-DPLUGIN_ARTRACK=ON"
    if [[ "$VM_HAS_BULLET" == "true" ]]; then
        if [ -d "$VM_BULLET_PATH" ]; then
            add-cmake-option "-DBULLET_ROOT=$VM_BULLET_PATH"
        fi
        add-cmake-option "-DPLUGIN_BULLETCOLLISIONDETECTION=ON"
    else
        add-cmake-option "-DPLUGIN_BULLETCOLLISIONDETECTION=OFF"
    fi
    if [[ "$VM_HAS_CGAL" == "true" ]]; then
        add-cmake-option "-DPLUGIN_CGALPLUGIN=ON"
    else
        add-cmake-option "-DPLUGIN_CGALPLUGIN=OFF"
    fi
    if [[ "$VM_HAS_ASSIMP" == "true" ]] || vm-is-windows; then
        # INFO: ColladaSceneLoader contains assimp for Windows (but that does not mean that VM has Assimp)
        add-cmake-option "-DPLUGIN_COLLADASCENELOADER=ON"
    else
        add-cmake-option "-DPLUGIN_COLLADASCENELOADER=OFF"
    fi
    add-cmake-option "-DPLUGIN_COMPLIANT=ON"
    add-cmake-option "-DPLUGIN_EXTERNALBEHAVIORMODEL=ON"
    add-cmake-option "-DPLUGIN_FLEXIBLE=ON"
    add-cmake-option "-DPLUGIN_IMAGE=ON"
    add-cmake-option "-DPLUGIN_INVERTIBLEFVM=ON"
    add-cmake-option "-DPLUGIN_MANIFOLDTOPOLOGIES=ON"
    add-cmake-option "-DPLUGIN_MANUALMAPPING=ON"
    if [[ "$VM_HAS_OPENCASCADE" == "true" ]]; then
        add-cmake-option "-DPLUGIN_MESHSTEPLOADER=ON"
    else
        add-cmake-option "-DPLUGIN_MESHSTEPLOADER=OFF"
    fi
    add-cmake-option "-DPLUGIN_MULTITHREADING=ON"
    add-cmake-option "-DPLUGIN_OPTITRACKNATNET=ON"
    add-cmake-option "-DPLUGIN_PLUGINEXAMPLE=ON"
    add-cmake-option "-DPLUGIN_REGISTRATION=ON"
    add-cmake-option "-DPLUGIN_SENSABLEEMULATION=ON"
    add-cmake-option "-DPLUGIN_SOFACARVING=ON"
    if [[ "$VM_HAS_CUDA" == "true" ]] && [[ "$COMPILER" != "clang"* ]]; then
        add-cmake-option "-DPLUGIN_SOFACUDA=ON"
    else
        add-cmake-option "-DPLUGIN_SOFACUDA=OFF"
    fi
    add-cmake-option "-DPLUGIN_SOFASIMPLEGUI=ON" # Not sure if worth maintaining
    add-cmake-option "-DPLUGIN_THMPGSPATIALHASHING=ON"
    add-cmake-option "-DPLUGIN_RIGIDSCALE=ON"
    
    add-cmake-option "-DPLUGIN_SOFAIMPLICITFIELD=ON"
    add-cmake-option "-DPLUGIN_SOFADISTANCEGRID=ON"
    add-cmake-option "-DPLUGIN_SOFAEULERIANFLUID=ON"
    add-cmake-option "-DPLUGIN_SOFAMISCCOLLISION=ON"
    add-cmake-option "-DPLUGIN_SOFAVOLUMETRICDATA=ON"
    
    
    # Always disabled
    add-cmake-option "-DPLUGIN_HAPTION=OFF" # Requires specific libraries.
    add-cmake-option "-DPLUGIN_PERSISTENTCONTACT=OFF" # Does not compile, but it just needs to be updated.    
    add-cmake-option "-DPLUGIN_SENSABLE=OFF" # Requires OpenHaptics libraries.    
    add-cmake-option "-DPLUGIN_SIXENSEHYDRA=OFF" # Requires Sixense libraries.    
    add-cmake-option "-DPLUGIN_SOFAHAPI=OFF" # Requires HAPI libraries.
    add-cmake-option "-DPLUGIN_XITACT=OFF" # Requires XiRobot library.
fi

# Options passed via the environnement
if [ -n "$CI_CMAKE_OPTIONS" ]; then
    add-cmake-option "$CI_CMAKE_OPTIONS"
fi



#############
# Configure #
#############

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
        msvc_comntools="$(get-msvc-comntools $COMPILER)"
        # Call vcvarsall.bat first to setup environment
        vcvarsall="call \"%${msvc_comntools}%\\..\\..\\VC\vcvarsall.bat\" $ARCHITECTURE"
        echo "Calling: $COMSPEC /c \"$vcvarsall & cmake $*\""
        $COMSPEC /c "$vcvarsall & cmake $*"
    else
        echo "Calling: cmake $@"
        cmake "$@"
    fi
}

cd "$BUILD_DIR"

echo "Calling cmake with the following options:"
echo "$cmake_options" | tr -s ' ' '\n' | grep -v "PLUGIN" | sort
echo "Enabled plugins:"
echo "$cmake_options" | tr -s ' ' '\n' | grep "PLUGIN" | grep "=ON" | sort
echo "Disabled plugins:"
echo "$cmake_options" | tr -s ' ' '\n' | grep "PLUGIN" | grep "=OFF" | sort

if [ -n "$full_build" ]; then
    call-cmake -G"$(generator)" $cmake_options "$SRC_DIR"
else
    call-cmake $cmake_options .
fi
