#!/bin/bash
set -o errexit # exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "--------------------------------------------"
echo "---- MacOS version"
system_profiler SPSoftwareDataType

echo "--------------------------------------------"
echo "---- AppleClang version"
clang --version

if [ ! -e "$(command -v brew)" ]; then
    echo "--------------------------------------------"
    echo "---- Install brew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh > /dev/null)"
fi

echo "--------------------------------------------"
echo "---- Install system utils"
brew install cmake ninja ccache coreutils

echo "--------------------------------------------"
echo "---- Install SOFA dependencies"
brew install boost eigen libpng libjpeg libtiff glew

echo "--------------------------------------------"
echo "---- Install Python, numpy, scipy, pybind11"
# Python 2
# brew install python@2.7
if [[ "$(python -V)" == *" 2.7"* ]]; then
    if [ ! -x "$(python -m pip)" ]; then
        curl -L https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py
        sudo python get-pip.py
    fi
    sudo python -m pip install --upgrade "pip == 20.3.4"
    sudo python -m pip install "scipy == 1.2.3" "matplotlib == 2.2.5" # "numpy == 1.16.6"
fi
# Python 3
brew install python@3.8
brew unlink python@3.10 || true
brew unlink python@3.9  || true
brew unlink python@3.8  || true
brew unlink python@3.7  || true
brew link --force python@3.8
python3 -m pip install --upgrade pip
python3 -m pip install numpy scipy pygame mypy pybind11-stubgen
brew install pybind11

echo "--------------------------------------------"
echo "---- Install Qt with online installer"
# Minimal Qt online version compatible with arm64: 6.2.0
# see 6.1.3: https://download.qt.io/online/qtsdkrepository/mac_x64/desktop/qt6_613/Updates.xml
#  vs 6.2.0: https://download.qt.io/online/qtsdkrepository/mac_x64/desktop/qt6_620/Updates.xml
QT_MAJOR=5
QT_MINOR=12
QT_PATCH=6
QT_COMPILER="clang_64"
QT_INSTALLDIR="$HOME/Qt"
if [ -d "$QT_INSTALLDIR" ]; then
    echo "Qt install dir already exists: $QT_INSTALLDIR"
    ls -la "$QT_INSTALLDIR"
else
    python3 -m pip install aqtinstall
    python3 -m aqt install-qt   --outputdir $QT_INSTALLDIR mac desktop $QT_MAJOR.$QT_MINOR.$QT_PATCH clang_64 -m qtcharts qtwebengine
    python3 -m aqt install-tool --outputdir $QT_INSTALLDIR mac desktop tools_ifw qt.tools.ifw.43
fi

echo "--------------------------------------------"
echo "---- Install plugins dependencies"
brew install assimp
brew install cgal
brew install opencascade
brew install lapack
# brew install homebrew/cask-drivers/nvidia-cuda

echo "--------------------------------------------"
echo "---- Set environment variables"
echo '
# Set python env vars
export PYTHONIOENCODING="UTF-8"
export PYTHONUSERBASE="/tmp/pythonuserbase"
mkdir -p "$PYTHONUSERBASE" && chmod -R 777 "$PYTHONUSERBASE"
# Qt env vars
export QTDIR="'$QT_INSTALLDIR'/'$QT_MAJOR'.'$QT_MINOR'.'$QT_PATCH'/clang_64"
export QTIFWDIR="'$QT_INSTALLDIR'/Tools/QtInstallerFramework/4.3"
export LD_LIBRARY_PATH="$QTDIR/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
# Add direct access to system utils in PATH
export PATH="\
/usr/local/opt/gnu-sed/libexec/gnubin:\
/usr/local/opt/coreutils/libexec/gnubin:\
/usr/local/opt/ccache/libexec:\
/usr/local/bin:/usr/local/lib:\
$QTDIR/bin:\
$QTIFWDIR/bin:\
$PATH"
' | sudo tee -a ~/.bash_profile




echo "--------------------------------------------"
