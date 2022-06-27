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
    SRC_DIR="$(cd "$2" && pwd)"
    CONFIG="$3"
    PLATFORM="$(get-platform-from-config "$CONFIG")"
    COMPILER="$(get-compiler-from-config "$CONFIG")"
    ARCHITECTURE="$(get-architecture-from-config "$CONFIG")"
    BUILD_TYPE="$4"
    BUILD_TYPE_CMAKE="$(get-build-type-cmake "$BUILD_TYPE")"
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


echo "--------------- configure.sh vars ---------------"
echo "BUILD_DIR = $BUILD_DIR"
echo "SRC_DIR = $SRC_DIR"
echo "CONFIG = $CONFIG"
echo "PLATFORM = $PLATFORM"
echo "COMPILER = $COMPILER"
echo "ARCHITECTURE = $ARCHITECTURE"
echo "BUILD_TYPE = $BUILD_TYPE"
echo "BUILD_TYPE_CMAKE = $BUILD_TYPE_CMAKE"
echo "BUILD_OPTIONS = $BUILD_OPTIONS"
echo "-------------------------------------------------"



########
# Init #
########

# Get Windows dependency pack
if vm-is-windows && [ ! -d "$SRC_DIR/lib" ]; then
    (
    cd "$SRC_DIR"
    echo "Copying dependency pack in the source tree."
    curl -L "https://github.com/guparan/ci/raw/tmp_windeppack/setup/WinDepPack.zip" --output dependencies_tmp.zip
    unzip dependencies_tmp.zip -d dependencies_tmp > /dev/null
    cp -rf dependencies_tmp/*/* "$SRC_DIR"
    rm -rf dependencies_tmp*
    )
fi

cmake_options=""
add-cmake-option() {
    cmake_options="$cmake_options $*"
}



#####################
# CMake env options #
#####################

add-cmake-option "-DCMAKE_BUILD_TYPE=$BUILD_TYPE_CMAKE"

# Compiler and cache
if vm-is-windows; then
    # Compiler
    # see comntools usage in call-cmake() for compiler selection on Windows

    # Cache
    if [ -e "$(command -v clcache)" ]; then
        export CLCACHE_DIR="J:/clcache"
        if [ -n "$EXECUTOR_LINK_WINDOWS_BUILD" ]; then
            export CLCACHE_BASEDIR="$EXECUTOR_LINK_WINDOWS_BUILD"
        else
            export CLCACHE_BASEDIR="$BUILD_DIR"
        fi
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
        ;;
        clang*)
            c_compiler="clang"
            cxx_compiler="clang++"
        ;;
        *) # other
            echo "Unknown compiler: $COMPILER"
            echo "Try a lucky guess..."
            c_compiler="$COMPILER"
            cxx_compiler="${COMPILER}++"
        ;;
    esac
    add-cmake-option "-DCMAKE_C_COMPILER=$c_compiler"
    add-cmake-option "-DCMAKE_CXX_COMPILER=$cxx_compiler"

    # Cache
    if [ -e "$(command -v ccache)" ]; then
        if [ -n "$WORKSPACE" ]; then
            # Useful for docker builds, set CCACHE_DIR at root of mounted volume
            # WARNING: this is dirty, it relies on "docker run" mount parameter "-v" in Jenkins job configuration
            workspace_root="$(echo "$WORKSPACE" | sed 's#/workspace/.*#/workspace#g')"
            export CCACHE_DIR="$workspace_root/.ccache"
        fi
        export CCACHE_BASEDIR="$(cd "$BUILD_DIR" && pwd)"
        export CCACHE_MAXSIZE="12G"
        if [ -n "$VM_CCACHE_MAXSIZE" ]; then
            export CCACHE_MAXSIZE="$VM_CCACHE_MAXSIZE"
        fi
        # export PATH="/usr/lib/ccache:$PATH" # /usr/lib/ccache contains symlinks for every compiler
        # export CC="ccache $c_compiler -Qunused-arguments -Wno-deprecated-declarations"
        # export CXX="ccache $cxx_compiler -Qunused-arguments -Wno-deprecated-declarations"
        add-cmake-option "-DCMAKE_C_COMPILER_LAUNCHER=ccache"
        add-cmake-option "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
        echo "----- ccache enabled -----"
        echo "CCACHE_DIR = $CCACHE_DIR"
        echo "CCACHE_BASEDIR = $CCACHE_BASEDIR"
        echo "CCACHE_MAXSIZE = $CCACHE_MAXSIZE"
        echo "--------------------------"
    fi
fi

# Set CMAKE_OSX_ARCHITECTURES
if vm-is-macos; then
    if [[ "$(uname -m)" == "arm64" ]]; then
        add-cmake-option "-DCMAKE_OSX_ARCHITECTURES=arm64"
    else
        add-cmake-option "-DCMAKE_OSX_ARCHITECTURES=x86_64"
    fi
fi

# Handle custom lib dirs
if vm-is-windows; then
    msvc_year="$(get-msvc-year $COMPILER)"
    qt_compiler="msvc${msvc_year}"
else
    qt_compiler="${COMPILER%-*}" # gcc-4.8 -> gcc
fi
if [[ "$ARCHITECTURE" != "x86" ]]; then
    qt_compiler="${qt_compiler}_64"
fi
if [[ "$VM_HAS_REQUIRED_LIBS" != "true" ]]; then
    echo "ERROR: VM_HAS_REQUIRED_LIBS is not true. Please make sure to have all required libs installed."
    exit 1
fi
if [ -d "$VM_QT_PATH" ]; then
    if [ -d "$VM_QT_PATH/${qt_compiler}" ]; then
        add-cmake-option "-DCMAKE_PREFIX_PATH=$VM_QT_PATH/${qt_compiler}"
    else
        add-cmake-option "-DCMAKE_PREFIX_PATH=$VM_QT_PATH"
    fi
fi
if vm-is-windows; then # Finding libs on Windows
    if [ -d "$VM_BOOST_PATH" ]; then
        add-cmake-option "-DBOOST_ROOT=$VM_BOOST_PATH"
    fi
    if [ -d "$VM_EIGEN3_PATH" ]; then
        export EIGEN3_ROOT_DIR="$VM_EIGEN3_PATH"
        # add-cmake-option "-DEIGEN3_ROOT=$VM_EIGEN3_PATH"
    fi
    if [ -e "$VM_PYTHON_EXECUTABLE" ]; then
        python2_path="$(dirname "$VM_PYTHON_EXECUTABLE")"
        if [[ "$ARCHITECTURE" == "x86" ]]; then
            python2_path="${python2_path}_x86"
        fi
        python2_exec="$python2_path/python.exe"
        python2_lib="$(ls $python2_path/libs/python[0-9][0-9].lib | head -n 1)"
        python2_include="$python2_path/include"
    fi
    if [ -e "$VM_PYTHON3_EXECUTABLE" ]; then
        python3_path="$(dirname "$VM_PYTHON3_EXECUTABLE")"
        if [[ "$ARCHITECTURE" == "x86" ]]; then
            python3_path="${python3_path}_x86"
        fi
        python3_exec="$python3_path/python.exe"
        python3_lib="$(ls $python3_path/libs/python[0-9][0-9].lib | head -n 1)"
        python3_include="$python3_path/include"
    fi
else
    if [[ -e "$VM_PYTHON_EXECUTABLE" ]] && [[ -e "${VM_PYTHON_EXECUTABLE}-config" ]]; then
        python2_config="${VM_PYTHON_EXECUTABLE}-config"
        python2_exec="$VM_PYTHON_EXECUTABLE"
        python2_lib=""
        python2_include=""
        for libdir in `$python2_config --ldflags | tr " " "\n" | grep  -o "/.*"`; do
            lib="$( find $libdir -maxdepth 1 -type l \( -name libpython2*.so -o -name libpython2*.dylib \) )"
            if [ -e "$lib" ]; then
                python2_lib="$lib"
                break
            fi
        done
        for includedir in `$python2_config --includes | tr " " "\n" | grep  -o "/.*"`; do
            if [ -e "$includedir/Python.h" ]; then
                python2_include="$includedir"
                break
            fi
        done
    fi
    if [[ -e "$VM_PYTHON3_EXECUTABLE" ]] && [[ -e "${VM_PYTHON3_EXECUTABLE}-config" ]]; then
        python3_config="${VM_PYTHON3_EXECUTABLE}-config"
        python3_exec="$VM_PYTHON3_EXECUTABLE"
        python3_lib=""
        python3_include=""
        for libdir in `$python3_config --ldflags | tr " " "\n" | grep  -o "/.*"`; do
            lib="$( find $libdir -maxdepth 1 -type l \( -name libpython3*.so -o -name libpython3*.dylib \) )"
            if [ -e "$lib" ]; then
                python3_lib="$lib"
                break
            fi
        done
        for includedir in `$python3_config --includes | tr " " "\n" | grep  -o "/.*"`; do
            if [ -e "$includedir/Python.h" ]; then
                python3_include="$includedir"
                break
            fi
        done
    fi
fi
if [ -e "$python2_exec" ] && [ -e "$python2_lib" ] && [ -e "$python2_include" ]; then
    add-cmake-option "-DPYTHON_EXECUTABLE=$python2_exec"
    add-cmake-option "-DPYTHON_LIBRARY=$python2_lib"
    add-cmake-option "-DPYTHON_INCLUDE_DIR=$python2_include"
    add-cmake-option "-DPython2_EXECUTABLE=$python2_exec"
    add-cmake-option "-DPython2_LIBRARY=$python2_lib"
    add-cmake-option "-DPython2_INCLUDE_DIR=$python2_include"
fi
if [ -e "$python3_exec" ] && [ -e "$python3_lib" ] && [ -e "$python3_include" ]; then
    add-cmake-option "-DPython_EXECUTABLE=$python3_exec"
    add-cmake-option "-DPython_LIBRARY=$python3_lib"
    add-cmake-option "-DPython_INCLUDE_DIR=$python3_include"
    add-cmake-option "-DPython3_EXECUTABLE=$python3_exec"
    add-cmake-option "-DPython3_LIBRARY=$python3_lib"
    add-cmake-option "-DPython3_INCLUDE_DIR=$python3_include"
fi
if [ -n "$VM_PYBIND11_CONFIG_EXECUTABLE" ]; then
    pybind11_cmakedir="$($VM_PYBIND11_CONFIG_EXECUTABLE --cmakedir)"
    if vm-is-windows; then
        pybind11_cmakedir="$(cd "$pybind11_cmakedir" && pwd -W)"
    fi
    add-cmake-option "-Dpybind11_ROOT=$pybind11_cmakedir"
    add-cmake-option "-Dpybind11_DIR=$pybind11_cmakedir"
fi
if [ -n "$VM_ASSIMP_PATH" ]; then
    add-cmake-option "-DASSIMP_ROOT_DIR=$VM_ASSIMP_PATH"
fi
if [ -d "$VM_BULLET_PATH" ]; then
    add-cmake-option "-DBULLET_ROOT=$VM_BULLET_PATH"
fi
if [ -d "$VM_CGAL_PATH" ]; then
    if vm-is-centos; then
        # Disable CGAL build test (see FindCGAL.cmake)
        add-cmake-option "-DCGAL_TEST_RUNS=TRUE"
    fi
    add-cmake-option "-DCGAL_DIR=$VM_CGAL_PATH"
fi
if [ -n "$VM_OPENCASCADE_PATH" ]; then
    add-cmake-option "-DSOFA_OPENCASCADE_ROOT=$VM_OPENCASCADE_PATH" # Needed by MeshSTEPLoader/FindOpenCascade.cmake
fi
if [ -n "$VM_CUDA_ARCH" ]; then
    add-cmake-option "-DSOFACUDA_ARCH=$VM_CUDA_ARCH"
fi
if [ -n "$VM_CUDA_HOST_COMPILER" ]; then
    add-cmake-option "-DCMAKE_CUDA_HOST_COMPILER=$VM_CUDA_HOST_COMPILER"
    add-cmake-option "-DCUDA_HOST_COMPILER=$VM_CUDA_HOST_COMPILER"
fi



######################
# CMake SOFA options #
######################

# Options common to all configurations
add-cmake-option "-DAPPLICATION_GETDEPRECATEDCOMPONENTS=ON"
add-cmake-option "-DSOFA_BUILD_APP_BUNDLE=OFF" # MacOS
add-cmake-option "-DSOFA_WITH_DEPRECATED_COMPONENTS=ON"
add-cmake-option "-DSOFAGUIQT_ENABLE_QDOCBROWSER=OFF"
add-cmake-option "-DSOFAGUIQT_ENABLE_NODEGRAPH=OFF"

# Build regression tests?
if in-array "run-regression-tests" "$BUILD_OPTIONS"; then
    add-cmake-option "-DAPPLICATION_REGRESSION_TEST=ON" "-DSOFA_FETCH_REGRESSION=ON"
else
    # clean eventual cached value
    add-cmake-option "-DAPPLICATION_REGRESSION_TEST=OFF" "-DSOFA_FETCH_REGRESSION=OFF"
fi

# Build with as few plugins/modules as possible (scope = minimal)
if in-array "build-scope-minimal" "$BUILD_OPTIONS"; then
    echo "Configuring with as few plugins/modules as possible (scope = minimal)"
    # Settings
    add-cmake-option "-DAPPLICATION_SOFAPHYSICSAPI=OFF"
    add-cmake-option "-DSOFA_BUILD_SCENECREATOR=OFF"
    add-cmake-option "-DSOFA_BUILD_TESTS=OFF"
    add-cmake-option "-DSOFA_FLOATING_POINT_TYPE=double"
    # Plugins (sofa/applications/plugins)
    add-cmake-option "-DPLUGIN_CIMGPLUGIN=OFF"
    add-cmake-option "-DPLUGIN_SOFAMATRIX=OFF"
    # Pluginized modules (sofa/modules)
    add-cmake-option "-DPLUGIN_SOFADENSESOLVER=OFF"
    add-cmake-option "-DPLUGIN_SOFAEXPORTER=OFF"
    add-cmake-option "-DPLUGIN_SOFAHAPTICS=OFF"
    add-cmake-option "-DPLUGIN_SOFAOPENGLVISUAL=OFF"
    add-cmake-option "-DPLUGIN_SOFAPRECONDITIONER=OFF"
    add-cmake-option "-DPLUGIN_SOFAVALIDATION=OFF"
    # GUI
    add-cmake-option "-DSOFAGUI_QGLVIEWER=OFF"
    add-cmake-option "-DSOFAGUI_QT=OFF"
    add-cmake-option "-DSOFAGUI_QTVIEWER=OFF"
    add-cmake-option "-DSOFA_NO_OPENGL=ON"
    add-cmake-option "-DSOFA_WITH_OPENGL=OFF"

# Build with the default plugins/modules (scope = standard)
elif in-array "build-scope-standard" "$BUILD_OPTIONS"; then
    echo "Configuring with the default plugins/modules (scope = standard)"
    add-cmake-option "-DAPPLICATION_SOFAPHYSICSAPI=ON"
    add-cmake-option "-DSOFA_BUILD_TUTORIALS=ON"
    add-cmake-option "-DSOFA_BUILD_TESTS=ON"
    add-cmake-option "-DSOFA_DUMP_VISITOR_INFO=ON"
    add-cmake-option "-DPLUGIN_SOFAPYTHON3=ON" "-DSOFA_FETCH_SOFAPYTHON3=ON"

# Build with as much plugins/modules as possible (scope = full)
elif in-array "build-scope-full" "$BUILD_OPTIONS"; then
    echo "Configuring with as much plugins/modules as possible (scope = full)"
    add-cmake-option "-DAPPLICATION_SOFAPHYSICSAPI=ON"
    add-cmake-option "-DSOFA_BUILD_TUTORIALS=ON"
    add-cmake-option "-DSOFA_BUILD_TESTS=ON"
    add-cmake-option "-DSOFA_DUMP_VISITOR_INFO=ON"
    add-cmake-option "-DPLUGIN_SOFAPYTHON3=ON" "-DSOFA_FETCH_SOFAPYTHON3=ON"
    # HeadlessRecorder (Linux only)
    if [[ "$(uname)" == "Linux" ]]; then
        id="$(cat /etc/*-release | grep "ID")"
        if [[ "$id" == *"centos"* ]]; then
            add-cmake-option "-DSOFAGUI_HEADLESS_RECORDER=OFF"
        else
            add-cmake-option "-DSOFAGUI_HEADLESS_RECORDER=ON"
        fi
    fi
    # NodeGraph
    if [ -n "$VM_NODEEDITOR_PATH" ]; then
        add-cmake-option "-DNodeEditor_ROOT=$VM_NODEEDITOR_PATH"
        add-cmake-option "-DNodeEditor_DIR=$VM_NODEEDITOR_PATH/lib/cmake/NodeEditor"
        add-cmake-option "-DSOFAGUIQT_ENABLE_NODEGRAPH=ON"
    fi
    # Plugins
    add-cmake-option "-DPLUGIN_BEAMADAPTER=ON -DSOFA_FETCH_BEAMADAPTER=ON"
    if [[ "$VM_HAS_BULLET" == "true" ]]; then
        add-cmake-option "-DPLUGIN_BULLETCOLLISIONDETECTION=ON"
    else
        add-cmake-option "-DPLUGIN_BULLETCOLLISIONDETECTION=OFF"
    fi
    if [[ "$VM_HAS_CGAL" == "true" ]]; then
        add-cmake-option "-DPLUGIN_CGALPLUGIN=OFF -DSOFA_FETCH_CGALPLUGIN=OFF"
    else
        add-cmake-option "-DPLUGIN_CGALPLUGIN=OFF -DSOFA_FETCH_CGALPLUGIN=OFF"
    fi
    if [[ "$VM_HAS_ASSIMP" == "true" ]]; then
        # INFO: ColladaSceneLoader contains assimp for Windows
        add-cmake-option "-DPLUGIN_COLLADASCENELOADER=ON"
        add-cmake-option "-DPLUGIN_SOFAASSIMP=ON"
    else
        add-cmake-option "-DPLUGIN_COLLADASCENELOADER=OFF"
        add-cmake-option "-DPLUGIN_SOFAASSIMP=OFF"
    fi
    add-cmake-option "-DPLUGIN_DIFFUSIONSOLVER=ON"
    add-cmake-option "-DPLUGIN_EXTERNALBEHAVIORMODEL=ON"
    add-cmake-option "-DPLUGIN_GEOMAGIC=ON"
    add-cmake-option "-DPLUGIN_IMAGE=ON"
    add-cmake-option "-DPLUGIN_INVERTIBLEFVM=ON -DSOFA_FETCH_INVERTIBLEFVM=ON"
    add-cmake-option "-DPLUGIN_MANIFOLDTOPOLOGIES=ON -DSOFA_FETCH_MANIFOLDTOPOLOGIES=ON"
    add-cmake-option "-DPLUGIN_MANUALMAPPING=ON"
    if [[ "$VM_HAS_OPENCASCADE" == "true" ]]; then
        add-cmake-option "-DPLUGIN_MESHSTEPLOADER=ON"
    else
        add-cmake-option "-DPLUGIN_MESHSTEPLOADER=OFF"
    fi
    add-cmake-option "-DPLUGIN_MULTITHREADING=ON"
    add-cmake-option "-DPLUGIN_OPTITRACKNATNET=ON -DSOFA_FETCH_OPTITRACKNATNET=ON"
    add-cmake-option "-DPLUGIN_PLUGINEXAMPLE=ON -DSOFA_FETCH_PLUGINEXAMPLE=ON"
    add-cmake-option "-DPLUGIN_REGISTRATION=ON -DSOFA_FETCH_REGISTRATION=ON"
    add-cmake-option "-DPLUGIN_SENSABLEEMULATION=ON"
    add-cmake-option "-DPLUGIN_SOFACARVING=ON"
    if [[ "$VM_HAS_CUDA" == "true" ]]; then
        add-cmake-option "-DPLUGIN_SOFACUDA=ON -DSOFA_FETCH_SOFACUDA=ON"
    else
        add-cmake-option "-DPLUGIN_SOFACUDA=OFF -DSOFA_FETCH_SOFACUDA=OFF"
    fi
    add-cmake-option "-DPLUGIN_SOFADISTANCEGRID=ON"
    add-cmake-option "-DPLUGIN_SOFAEULERIANFLUID=ON"
    add-cmake-option "-DPLUGIN_SOFAGLFW=ON" "-DPLUGIN_SOFAIMGUI=OFF" "-DAPPLICATION_RUNSOFAGLFW=ON" "-DSOFA_FETCH_SOFAGLFW=ON"
    add-cmake-option "-DPLUGIN_SOFAIMPLICITFIELD=ON"
    add-cmake-option "-DPLUGIN_SOFASIMPLEGUI=ON" # Not sure if worth maintaining
    add-cmake-option "-DPLUGIN_SOFASPHFLUID=ON"
    add-cmake-option "-DPLUGIN_COLLISIONOBBCAPSULE=ON"
    add-cmake-option "-DPLUGIN_THMPGSPATIALHASHING=OFF -DSOFA_FETCH_THMPGSPATIALHASHING=ON"
fi

# Generate binaries?
if in-array "build-release-package" "$BUILD_OPTIONS"; then
    add-cmake-option "-DSOFA_BUILD_RELEASE_PACKAGE=ON"
    if [[ "$BUILD_TYPE_CMAKE" == "Release" ]]; then
        add-cmake-option "-DCMAKE_BUILD_TYPE=MinSizeRel"
    fi
    if [ -z "$QTIFWDIR"]; then
        qt_root="$VM_QT_PATH"
        if [ ! -d "$qt_root" ] && [ -d "$QTDIR" ] && [ -d "$( dirname "$(dirname "$QTDIR")" )" ]; then
            qt_root="$( dirname "$(dirname "$QTDIR")" )"
        fi
        for dir in "$qt_root/Tools/QtInstallerFramework/"*; do
            if [ -d "$dir" ]; then
                export QTIFWDIR="$dir" # take the first one
                break
            fi
        done
    fi
    add-cmake-option \
        "-DCPACK_BINARY_IFW=OFF" "-DCPACK_BINARY_NSIS=OFF" "-DCPACK_BINARY_ZIP=OFF" \
        "-DCPACK_BINARY_BUNDLE=OFF" "-DCPACK_BINARY_DEB=OFF" "-DCPACK_BINARY_DRAGNDROP=OFF" \
        "-DCPACK_BINARY_FREEBSD=OFF" "-DCPACK_BINARY_OSXX11=OFF" "-DCPACK_BINARY_PACKAGEMAKER=OFF" \
        "-DCPACK_BINARY_PRODUCTBUILD=OFF" "-DCPACK_BINARY_RPM=OFF" "-DCPACK_BINARY_STGZ=OFF" \
        "-DCPACK_BINARY_TBZ2=OFF" "-DCPACK_BINARY_TGZ=OFF" "-DCPACK_BINARY_TXZ=OFF" \
        "-DCPACK_SOURCE_RPM=OFF" "-DCPACK_SOURCE_TBZ2=OFF" "-DCPACK_SOURCE_TGZ=OFF" \
        "-DCPACK_SOURCE_TXZ=OFF" "-DCPACK_SOURCE_TZ=OFF"
    if vm-is-windows; then
        add-cmake-option "-DCPACK_GENERATOR=ZIP;NSIS"
        add-cmake-option "-DCPACK_BINARY_ZIP=ON"
        add-cmake-option "-DCPACK_BINARY_NSIS=ON"
    elif [ -n "$QTIFWDIR" ]; then
        add-cmake-option "-DCPACK_GENERATOR=ZIP;IFW"
        add-cmake-option "-DCPACK_BINARY_ZIP=ON"
        add-cmake-option "-DCPACK_BINARY_IFW=ON"
    else
        # ZIP only
        add-cmake-option "-DCPACK_GENERATOR=ZIP"
        add-cmake-option "-DCPACK_BINARY_ZIP=ON"
    fi
fi

# Options passed via the environnement
if [ -n "$CI_CMAKE_OPTIONS" ]; then
    add-cmake-option "$CI_CMAKE_OPTIONS"
fi



#############
# Configure #
#############

echo "Calling cmake with the following options:"
echo "$cmake_options" | tr -s " " "\n" | grep -v "MODULE_" | grep -v "PLUGIN_" | sort
echo "Enabled modules and plugins:"
echo "$cmake_options" | tr -s " " "\n" | grep "MODULE_" | grep "=ON" | sort
echo "$cmake_options" | tr -s " " "\n" | grep "PLUGIN_" | grep "=ON" | sort
echo "Disabled modules and plugins:"
echo "$cmake_options" | tr -s " " "\n" | grep "MODULE_" | grep "=OFF" | sort
echo "$cmake_options" | tr -s " " "\n" | grep "PLUGIN_" | grep "=OFF" | sort

if [ -n "$full_build" ]; then
    relative_src="$(realpath --relative-to="$BUILD_DIR" "$SRC_DIR")"
    call-cmake "$BUILD_DIR" -G"$(generator)" $cmake_options "$relative_src"
else
    call-cmake "$BUILD_DIR" -G"$(generator)" $cmake_options .
fi
