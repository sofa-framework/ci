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
echo "---- Install Qt with installer"
QT_MAJOR=5
QT_MINOR=12
QT_PATCH=6
QT_COMPILER="clang_64"
QT_ACCOUNT_DIR="$HOME/Library/Application Support/Qt"
QT_INSTALL_DIR="$HOME/Qt"
if [ -d "$QT_INSTALL_DIR" ]; then
    echo "Qt install dir already exists: $QT_INSTALL_DIR"
    ls -la "$QT_INSTALL_DIR"
else
    mkdir -p "$QT_ACCOUNT_DIR"
    cp -f "$SCRIPT_DIR/qt/qtaccount.ini" "$QT_ACCOUNT_DIR/qtaccount.ini"
    cat "$SCRIPT_DIR/qt/qtinstaller_controlscript_template.qs" \
        | sed 's:_QTVERSION_:'"$QT_MAJOR$QT_MINOR$QT_PATCH"':g' \
        | sed 's:_QTINSTALLDIR_:'"$QT_INSTALL_DIR"':g' \
        | sed 's:_QTCOMPILER_:'"$QT_COMPILER"':g' \
        > /tmp/qtinstaller_controlscript.qs
    curl -L https://download.qt.io/official_releases/online_installers/qt-unified-mac-x64-online.dmg --output /tmp/qt-unified-mac-x64-online.dmg
    hdiutil attach /tmp/qt-unified-mac-x64-online.dmg
    /Volumes/qt-unified-macOS-*/qt-unified-macOS-*/Contents/MacOS/qt-unified-macOS-* --script /tmp/qtinstaller_controlscript.qs --verbose
    hdiutil unmount /Volumes/qt-unified-macOS-*
fi

echo "--------------------------------------------"
echo "---- Install plugins dependencies"
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
brew unlink python@3.10
brew unlink python@3.9
brew unlink python@3.8
brew unlink python@3.7
brew link --force python@3.8
python3 -m pip install --upgrade pip
python3 -m pip install numpy scipy pygame pybind11

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
export LD_LIBRARY_PATH="$QTDIR/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
# Add direct access to system utils in PATH
export PATH="\
/usr/local/opt/gnu-sed/libexec/gnubin:\
/usr/local/opt/coreutils/libexec/gnubin:\
/usr/local/opt/ccache/libexec:\
/usr/local/bin:/usr/local/lib:\
$QTDIR/bin:\
$PATH"
' | sudo tee -a ~/.bash_profile




echo "--------------------------------------------"
