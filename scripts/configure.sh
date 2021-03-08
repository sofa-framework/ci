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
    curl -L "https://www.sofa-framework.org/download/WinDepPack/$COMPILER/latest" --output dependencies_tmp.zip
    unzip dependencies_tmp.zip -d dependencies_tmp > /dev/null
    cp -rf dependencies_tmp/*/* "$SRC_DIR"
    rm -rf dependencies_tmp*
    )
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
    if [ -x "$(command -v ccache)" ]; then
        if [ -n "$WORKSPACE" ]; then
            # Useful for docker builds, set CCACHE_DIR at root of mounted volume
            # WARNING: this is dirty, it relies on "docker run" mount parameter "-v" in Jenkins job configuration
            workspace_root="$(echo "$WORKSPACE" | sed 's#/workspace/.*#/workspace#g')"
            export CCACHE_DIR="$workspace_root/.ccache"
        fi
        export CCACHE_BASEDIR="$(cd "$BUILD_DIR" && pwd)"
        export CCACHE_MAXSIZE="12G"
        # export PATH="/usr/lib/ccache:$PATH" # /usr/lib/ccache contains symlinks for every compiler
        # export CC="ccache $c_compiler -Qunused-arguments -Wno-deprecated-declarations"
        # export CXX="ccache $cxx_compiler -Qunused-arguments -Wno-deprecated-declarations"
        add-cmake-option "-DCMAKE_C_COMPILER_LAUNCHER=ccache"
        add-cmake-option "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
        echo "----- ccache enabled -----"
        echo "CCACHE_DIR = $CCACHE_DIR"
        echo "CCACHE_BASEDIR = $CCACHE_BASEDIR"
        echo "CCACHE_MAXSIZE = $CCACHE_MAXSIZE"
        echo "CC = $CC"
        echo "CXX = $CXX"
        echo "--------------------------"
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
    add-cmake-option "-DCMAKE_PREFIX_PATH=$VM_QT_PATH/${qt_compiler}"
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
        python2_name="$(basename $VM_PYTHON_EXECUTABLE)"
        python2_config="${VM_PYTHON_EXECUTABLE}-config"
        python2_exec="$VM_PYTHON_EXECUTABLE"
        python2_lib=""
        python2_include=""
        for libdir in `$python2_config --ldflags | tr " " "\n" | grep  -o "/.*"`; do
            lib="$( find $libdir -maxdepth 1 -type l \( -name lib${python2_name}.so -o -name lib${python2_name}.dylib \) )"
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
            lib="$( find $libdir -maxdepth 1 -type l \( -name lib${python3_name}.so -o -name lib${python3_name}.dylib \) )"
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
if [ -e "$python2_path" ]; then
    add-cmake-option "-DPYTHON_ROOT_DIR=$python2_path"
    add-cmake-option "-DPYTHON_ROOT=$python2_path"
    add-cmake-option "-DPython2_ROOT_DIR=$python2_path"
    add-cmake-option "-DPython2_ROOT=$python2_path"
    export PYTHON_ROOT_DIR="$python2_path"
    export PYTHON_ROOT="$python2_path"
    export Python2_ROOT_DIR="$python2_path"
    export Python2_ROOT="$python2_path"
fi
if [ -e "$python3_path" ]; then
    add-cmake-option "-DPython_ROOT_DIR=$python3_path"
    add-cmake-option "-DPython_ROOT=$python3_path"
    add-cmake-option "-DPython3_ROOT_DIR=$python3_path"
    add-cmake-option "-DPython3_ROOT=$python3_path"
    export Python_ROOT_DIR="$python3_path"
    export Python_ROOT="$python3_path"
    export Python3_ROOT_DIR="$python3_path"
    export Python3_ROOT="$python3_path"
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

# Options common to all configurations
add-cmake-option "-DCMAKE_BUILD_TYPE=$(tr '[:lower:]' '[:upper:]' <<< ${BUILD_TYPE:0:1})${BUILD_TYPE:1}"
add-cmake-option "-DCMAKE_COLOR_MAKEFILE=OFF"
add-cmake-option "-DSOFA_WITH_DEPRECATED_COMPONENTS=ON"
add-cmake-option "-DSOFAGUI_BUILD_TESTS=OFF"
add-cmake-option "-DSOFAGUIQT_ENABLE_NODEGRAPH=OFF"
add-cmake-option "-DSOFA_BUILD_APP_BUNDLE=OFF" # MacOS

add-cmake-option "-DPLUGIN_CIMGPLUGIN=ON"
add-cmake-option "-DPLUGIN_SOFAMISCCOLLISION=ON"
add-cmake-option "-DPLUGIN_SOFAPYTHON=ON"
add-cmake-option "-DPLUGIN_SOFAPYTHON3=ON" "-DSOFA_FETCH_SOFAPYTHON3=ON"
add-cmake-option "-DSOFA_ENABLE_SOFT_DEPS_TO_SOFAPYTHON=OFF"

add-cmake-option "-DMODULE_SOFADENSESOLVER=ON"
add-cmake-option "-DMODULE_SOFAEXPORTER=ON"
add-cmake-option "-DMODULE_SOFAHAPTICS=ON"
add-cmake-option "-DMODULE_SOFANONUNIFORMFEM=ON"
add-cmake-option "-DMODULE_SOFAOPENGLVISUAL=ON"
add-cmake-option "-DMODULE_SOFAPRECONDITIONER=ON"
add-cmake-option "-DMODULE_SOFASPARSESOLVER=ON"
add-cmake-option "-DMODULE_SOFAVALIDATION=ON"

if in-array "run-regression-tests" "$BUILD_OPTIONS"; then
    add-cmake-option "-DAPPLICATION_REGRESSION_TEST=ON" "-DSOFA_FETCH_REGRESSION=ON"
else
    # clean eventual cached value
    add-cmake-option "-DAPPLICATION_REGRESSION_TEST=OFF" "-DSOFA_FETCH_REGRESSION=OFF"
fi

if in-array "build-release-package" "$BUILD_OPTIONS"; then
    add-cmake-option "-DSOFA_BUILD_RELEASE_PACKAGE=ON"

    if [ -d "$VM_QT_PATH/Tools/QtInstallerFramework" ]; then
        for dir in "$VM_QT_PATH/Tools/QtInstallerFramework/"*; do
            if [ -d "$dir" ]; then
                export QTIFWDIR="$dir" # used for packaging on Linux
                break
            fi
        done
    fi
    # Default OFF
    add-cmake-option "-DCPACK_BINARY_BUNDLE=OFF"
    add-cmake-option "-DCPACK_BINARY_DEB=OFF"
    add-cmake-option "-DCPACK_BINARY_DRAGNDROP=OFF"
    add-cmake-option "-DCPACK_BINARY_FREEBSD=OFF"
    add-cmake-option "-DCPACK_BINARY_IFW=OFF"
    add-cmake-option "-DCPACK_BINARY_NSIS=OFF"
    add-cmake-option "-DCPACK_BINARY_OSXX11=OFF"
    add-cmake-option "-DCPACK_BINARY_PACKAGEMAKER=OFF"
    add-cmake-option "-DCPACK_BINARY_PRODUCTBUILD=OFF"
    add-cmake-option "-DCPACK_BINARY_RPM=OFF"
    add-cmake-option "-DCPACK_BINARY_STGZ=OFF"
    add-cmake-option "-DCPACK_BINARY_TBZ2=OFF"
    add-cmake-option "-DCPACK_BINARY_TGZ=OFF"
    add-cmake-option "-DCPACK_BINARY_TXZ=OFF"
    add-cmake-option "-DCPACK_BINARY_ZIP=OFF"
    add-cmake-option "-DCPACK_SOURCE_RPM=OFF"
    add-cmake-option "-DCPACK_SOURCE_TBZ2=OFF"
    add-cmake-option "-DCPACK_SOURCE_TGZ=OFF"
    add-cmake-option "-DCPACK_SOURCE_TXZ=OFF"
    add-cmake-option "-DCPACK_SOURCE_TZ=OFF"
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
else # This is not a "package" build
    add-cmake-option "-DSOFA_BUILD_TUTORIALS=ON"
    add-cmake-option "-DSOFA_BUILD_TESTS=ON"
    add-cmake-option "-DSOFA_BUILD_METIS=ON"
    add-cmake-option "-DAPPLICATION_SOFAPHYSICSAPI=ON"
    add-cmake-option "-DAPPLICATION_MODELER=ON"
    add-cmake-option "-DAPPLICATION_GETDEPRECATEDCOMPONENTS=ON"
    if [ -n "$VM_NODEEDITOR_PATH" ]; then
        add-cmake-option "-DNodeEditor_ROOT=$VM_NODEEDITOR_PATH"
        add-cmake-option "-DNodeEditor_DIR=$VM_NODEEDITOR_PATH/lib/cmake/NodeEditor"
        add-cmake-option "-DSOFAGUIQT_ENABLE_NODEGRAPH=ON"
    fi

    if in-array "build-all-plugins" "$BUILD_OPTIONS"; then 
        # Build with as many options enabled as possible
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
        
        ### Modules
        add-cmake-option "-DMODULE_SOFACOMBINATORIALMAPS=ON"
        add-cmake-option "-DMODULE_SOFACOMBINATORIALMAPS_FETCH_CGOGN=ON"

        ### Plugins
        add-cmake-option "-DPLUGIN_ARTRACK=ON"
        if [[ "$VM_HAS_BULLET" == "true" ]]; then
            add-cmake-option "-DPLUGIN_BULLETCOLLISIONDETECTION=ON"
        else
            add-cmake-option "-DPLUGIN_BULLETCOLLISIONDETECTION=OFF"
        fi
        if [[ "$VM_HAS_CGAL" == "true" ]]; then
            add-cmake-option "-DPLUGIN_CGALPLUGIN=ON"
        else
            add-cmake-option "-DPLUGIN_CGALPLUGIN=OFF"
        fi
        if [[ "$VM_HAS_ASSIMP" == "true" ]]; then
            # INFO: ColladaSceneLoader contains assimp for Windows
            add-cmake-option "-DPLUGIN_COLLADASCENELOADER=ON"
            add-cmake-option "-DPLUGIN_SOFAASSIMP=ON"
        else
            add-cmake-option "-DPLUGIN_COLLADASCENELOADER=OFF"
            add-cmake-option "-DPLUGIN_SOFAASSIMP=OFF"
        fi
        add-cmake-option "-DPLUGIN_COMMUNICATION=ON"
        add-cmake-option "-DPLUGIN_COMPLIANT=ON -DSOFA_FETCH_COMPLIANT=ON"
        add-cmake-option "-DPLUGIN_DIFFUSIONSOLVER=ON"
        add-cmake-option "-DPLUGIN_EXTERNALBEHAVIORMODEL=ON"
        add-cmake-option "-DPLUGIN_FLEXIBLE=ON -DSOFA_FETCH_FLEXIBLE=ON"
        add-cmake-option "-DPLUGIN_IMAGE=ON"
        add-cmake-option "-DPLUGIN_INVERTIBLEFVM=ON -DSOFA_FETCH_INVERTIBLEFVM=ON"
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
        if [[ "$VM_HAS_CUDA" == "true" ]]; then
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
        add-cmake-option "-DPLUGIN_SOFASPHFLUID=ON"
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
    call-cmake "$BUILD_DIR" $cmake_options .
fi 
