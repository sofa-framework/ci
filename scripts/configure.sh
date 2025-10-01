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

# Input <ci-depends-on-flags> adds cmake flags for configure to handle ci-depends-on. If no ci-depends-on is used, then the string should be equal to "no-ci-depends-on"

## Checks

usage() {
    echo "Usage: configure.sh <build-dir> <src-dir> <config> <ci-depends-on-flags> <build-type> <build-options>"
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
    CI_DEPENDS_ON_FLAGS="$4"
    if [ "$CI_DEPENDS_ON_FLAGS" == "no-additionnal-cmake-flags" ]; then
        CI_DEPENDS_ON_FLAGS=""
    fi
    BUILD_TYPE="$5"
    BUILD_TYPE_CMAKE="$(get-build-type-cmake "$BUILD_TYPE")"
    BUILD_OPTIONS="${*:6}"
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
echo "CI_DEPENDS_ON_FLAGS = $CI_DEPENDS_ON_FLAGS"
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
    curl -L "https://www.sofa-framework.org/download/WinDepPack/latest/" --output dependencies_tmp.zip
    unzip dependencies_tmp.zip -d dependencies_tmp > /dev/null
    cp -rf dependencies_tmp/*/* "$SRC_DIR"
    rm -rf dependencies_tmp*
    )
fi

cmake_options="$CI_DEPENDS_ON_FLAGS"
add-cmake-option() {
    cmake_options="$cmake_options $*"
}



#####################
# CMake env options #
#####################

add-cmake-option "-DCMAKE_BUILD_TYPE=$BUILD_TYPE_CMAKE"

# Compiler and cache
if vm-is-windows; then

	echo "clcache is disabled temporarly"
    # Compiler
    # see comntools usage in call-cmake() for compiler selection on Windows

    # Cache //TODO : make clcache work on windows builder
    # if [ -e "$(command -v clcache)" ]; then
        # export CLCACHE_DIR="C:/clcache"
        # if [ -n "$EXECUTOR_LINK_WINDOWS_BUILD" ]; then
            # export CLCACHE_BASEDIR="$EXECUTOR_LINK_WINDOWS_BUILD"
        # else
            # export CLCACHE_BASEDIR="$BUILD_DIR"
        # fi
        # #export CLCACHE_HARDLINK=1 # this may cause cache corruption. see https://github.com/frerich/clcache/issues/282
        # export CLCACHE_OBJECT_CACHE_TIMEOUT_MS=3600000
        # clcache -M 17179869184 # Set cache size to 1024*1024*1024*16 = 16 GB

        # add-cmake-option "-DCMAKE_C_COMPILER=clcache"
        # add-cmake-option "-DCMAKE_CXX_COMPILER=clcache"
    # fi
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
    elif find $VM_QT_PATH/*/include/QtCore -type f -name "QtCore" > /dev/null; then
        # Trying to find a qt compiler directory
        qt_path_and_compiler="$(ls -d $VM_QT_PATH/*_64 | head -n 1)"
        add-cmake-option "-DCMAKE_PREFIX_PATH=$qt_path_and_compiler"
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
        python2_lib="$(ls $python2_path/libs/python[0-9][0-9]*.lib | head -n 1)"
        python2_include="$python2_path/include"
    fi
    if [ -e "$VM_PYTHON3_EXECUTABLE" ]; then
        python3_path="$(dirname "$VM_PYTHON3_EXECUTABLE")"
        if [[ "$ARCHITECTURE" == "x86" ]]; then
            python3_path="${python3_path}_x86"
        fi
        python3_exec="$python3_path/python.exe"
        python3_lib="$(ls $python3_path/libs/python[0-9][0-9]*.lib | head -n 1)"
        python3_include="$python3_path/include"
    fi
else
    if [[ -e "$VM_PYTHON_EXECUTABLE" ]] && [[ -e "${VM_PYTHON_EXECUTABLE}-config" ]]; then
        python2_name="$(basename $VM_PYTHON_EXECUTABLE)"
        python2_config="${VM_PYTHON_EXECUTABLE}-config"
        python2_exec="$VM_PYTHON_EXECUTABLE"
        python2_lib=""
        python2_include=""
        for libdir in `$python2_config --ldflags | tr " " "\n" | grep  -o "/.*"`; do
            lib="$( find $libdir -maxdepth 1 -type l \( -name lib${python2_name}*.so -o -name lib${python2_name}*.dylib \) | head -n 1 )"
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
        python3_name="$(basename $VM_PYTHON3_EXECUTABLE)"
        python3_config="${VM_PYTHON3_EXECUTABLE}-config"
        python3_exec="$VM_PYTHON3_EXECUTABLE"
        python3_lib=""
        python3_include=""
        for libdir in `$python3_config --ldflags | tr " " "\n" | grep  -o "/.*"`; do
            lib="$( find $libdir -maxdepth 1 -type l \( -name lib${python3_name}*.so -o -name lib${python3_name}*.dylib \) | head -n 1 )"
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
echo "---------------"
echo "python3_exec = $python3_exec"
echo "python3_lib = $python3_lib"
echo "python3_include = $python3_include"
echo "---------------"
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

if [ -n "$VM_CUDA_HOST_COMPILER" ]; then
    add-cmake-option "-DCMAKE_CUDA_HOST_COMPILER=$VM_CUDA_HOST_COMPILER"
    add-cmake-option "-DCUDA_HOST_COMPILER=$VM_CUDA_HOST_COMPILER"
fi

# VM dependent deactivation
if [ -n "$VM_NODEEDITOR_PATH" ]; then
    add-cmake-option "-DNodeEditor_ROOT=$VM_NODEEDITOR_PATH"
    add-cmake-option "-DNodeEditor_DIR=$VM_NODEEDITOR_PATH/lib/cmake/NodeEditor"
fi



######################
# CMake SOFA options #
######################

# Build with as few plugins/modules as possible (scope = minimal)
if in-array "build-scope-minimal" "$BUILD_OPTIONS"; then
    PRESETS="minimal"

    echo "Configuring with as few plugins/modules as possible (scope = minimal)"


# Build with the default plugins/modules (scope = standard)
elif in-array "build-scope-standard" "$BUILD_OPTIONS"; then
    PRESETS="standard"
    echo "Configuring with the default plugins/modules (scope = standard)"


# Build with the default plugins/modules (scope = standard)
elif in-array "build-scope-supported-plugins" "$BUILD_OPTIONS"; then
    PRESETS="supported-plugins"
    echo "Configuring with the supported plugins/modules (scope = supported-plugins)"

    if [[ "$VM_HAS_CGAL" == "false" ]]; then
        add-cmake-option "-DPLUGIN_CGALPLUGIN=OFF -DSOFA_FETCH_CGALPLUGIN=OFF"
    elif  vm-is-ubuntu || vm-is-centos; then
        add-cmake-option "-DSOFA_CGALPLUGIN_LIMIT_NINJA_JOB_POOL=ON"
    fi

    if [[ "$VM_HAS_CUDA" == "true" ]]; then
        add-cmake-option "-DSOFACUDA_DOUBLE=ON"
        if in-array "build-release-package" "$BUILD_OPTIONS"; then
            add-cmake-option "-DCMAKE_CUDA_ARCHITECTURES=60;61;70;75;80;86;89"
        else
            add-cmake-option "-DCMAKE_CUDA_ARCHITECTURES=60;89"
        fi
        add-cmake-option "-DPLUGIN_VOLUMETRICRENDERING_CUDA=ON"
        add-cmake-option "-DPLUGIN_SOFADISTANCEGRID_CUDA=ON"
    else
        add-cmake-option "-DPLUGIN_SOFACUDA=OFF"
        #Deactivate all CUDA modules based on naming convention 'XXX.CUDA" that creates a CMake flag "PLUGIN_XXX_CUDA" thus the double grep 
     	add-cmake-option "$(cat $SRC_DIR/CMakePresets.json | grep PLUGIN_ | grep _CUDA | awk -F'"' '{ print "-D"$2"=OFF" }' | sort | uniq)"
    fi

# Build with as much plugins/modules as possible (scope = full)
elif in-array "build-scope-full" "$BUILD_OPTIONS"; then
    PRESETS="full"
    echo "Configuring with full set of plugins (scope = full)"


    if [[ "$VM_HAS_CGAL" == "false" ]]; then
        add-cmake-option "-DPLUGIN_CGALPLUGIN=OFF -DSOFA_FETCH_CGALPLUGIN=OFF"
    elif  vm-is-ubuntu || vm-is-centos; then
        add-cmake-option "-DSOFA_CGALPLUGIN_LIMIT_NINJA_JOB_POOL=ON"
    fi

    if [[ "$VM_HAS_ASSIMP" == "false" ]]; then
        add-cmake-option "-DPLUGIN_COLLADASCENELOADER=OFF"
        add-cmake-option "-DPLUGIN_SOFAASSIMP=OFF"
    fi
    if [[ "$VM_HAS_OPENCASCADE" == "false" ]]; then
        add-cmake-option "-DPLUGIN_MESHSTEPLOADER=OFF"
    fi

    if [[ "$VM_HAS_CUDA" == "true" ]]; then
        add-cmake-option "-DSOFACUDA_DOUBLE=ON"
        if in-array "build-release-package" "$BUILD_OPTIONS"; then
            add-cmake-option "-DCMAKE_CUDA_ARCHITECTURES=60;61;70;75;80;86;89"
        else
            add-cmake-option "-DCMAKE_CUDA_ARCHITECTURES=60;89"
        fi
        add-cmake-option "-DPLUGIN_VOLUMETRICRENDERING_CUDA=ON"
        add-cmake-option "-DPLUGIN_SOFADISTANCEGRID_CUDA=ON"
    else
        add-cmake-option "-DPLUGIN_SOFACUDA=OFF"
        #Deactivate all CUDA modules based on naming convention 'XXX.CUDA" that creates a CMake flag "PLUGIN_XXX_CUDA" thus the double grep 
     	add-cmake-option "$(cat $SRC_DIR/CMakePresets.json | grep PLUGIN_ | grep _CUDA | awk -F'"' '{ print "-D"$2"=OFF" }' | sort | uniq)"
    fi

fi


# Generate binaries?
if in-array "build-release-package" "$BUILD_OPTIONS"; then
    add-cmake-option "-DSOFA_WITH_DEVTOOLS=OFF"
    add-cmake-option "-DSOFA_DUMP_VISITOR_INFO=OFF"
    add-cmake-option "-DSOFA_BUILD_RELEASE_PACKAGE=ON"
    #If in release, do not activate dev tools but activate Regression anyway. 
    add-cmake-option "-DSOFA_FETCH_REGRESSION=ON"
    add-cmake-option "-DAPPLICATION_REGRESSION_TEST=ON"

    if [[ "$BUILD_TYPE_CMAKE" == "Release" ]]; then
        add-cmake-option "-DCMAKE_BUILD_TYPE=MinSizeRel"
    fi
    if [ -z "$QTIFWDIR" ]; then
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

else
    #If not in release activate DEV tools
    PRESETS=${PRESETS}-dev
fi


add-cmake-option "--preset=$PRESETS"


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


if [ -z "$( ls -A "$BUILD_DIR" )" ]; then
    relative_src="$(realpath --relative-to="$BUILD_DIR" "$SRC_DIR")"
    call-cmake "$BUILD_DIR" -G"$(generator)" $cmake_options "$relative_src"
else
    call-cmake "$BUILD_DIR" -G"$(generator)" $cmake_options .
fi
