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
brew install cmake ninja ccache coreutils git sshpass

echo "--------------------------------------------"
echo "---- Install SOFA dependencies"
brew install boost eigen libpng libjpeg libtiff glew

echo "--------------------------------------------"
echo "---- Install Python, numpy, scipy, pybind11"
# Python 3
brew install python@3.12
brew install python@3.13
brew install python@3.14

brew unlink python@3.14 || true
brew unlink python@3.13  || true
brew unlink python@3.12  || true

brew link --force python@3.12
python3.12 -m pip install --upgrade pip
python3.12 -m pip install numpy scipy pygame pybind11==3.0.1 mypy pybind11-stubgen rpyc prettytable ct3 --break-system-packages

brew unlink python@3.12  || true
brew link --force python@3.13
python3.13 -m pip install --upgrade pip
python3.13 -m pip install numpy scipy pygame pybind11==3.0.1 mypy pybind11-stubgen rpyc prettytable ct3 --break-system-packages

brew unlink python@3.13  || true
brew link --force python@3.14
python3.14 -m pip install --upgrade pip
python3.14 -m pip install numpy scipy pygame-ce pybind11==3.0.1 mypy pybind11-stubgen rpyc prettytable ct3 --break-system-packages

brew unlink python@3.14  || true
brew link --force python@3.12



echo "--------------------------------------------"
echo "---- Install plugins dependencies"
brew install assimp
brew install cgal
brew install opencascade
brew install lapack
brew install tinyxml2
brew install gh

# brew install homebrew/cask-drivers/nvidia-cuda

echo "--------------------------------------------"
echo "---- Set environment variables"
echo '
# Set python env vars
export PYTHONIOENCODING="UTF-8"
export PYTHONUSERBASE="/tmp/pythonuserbase"
mkdir -p "$PYTHONUSERBASE" && chmod -R 777 "$PYTHONUSERBASE"
# Add direct access to system utils in PATH
export PATH="\
/usr/local/opt/gnu-sed/libexec/gnubin:\
/usr/local/opt/coreutils/libexec/gnubin:\
/usr/local/opt/ccache/libexec:\
/usr/local/bin:/usr/local/lib:\
$PATH"
' | sudo tee -a ~/.bash_profile




echo "--------------------------------------------"
