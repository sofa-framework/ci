@echo off

REM Install is MINIMAL by default
REM Add "FULL" argument to enable FULL install
set MINIMAL_INSTALL="TRUE"
if "%1" == "FULL" set "MINIMAL_INSTALL="

set SCRIPTDIR=%~dp0
set WORKDIR=%TEMP%\%~n0
rmdir /S /Q %WORKDIR%
mkdir %WORKDIR%

REM Install Chocolatey (will also install refreshenv command)
powershell -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))"
set AddToUserPATH=%ALLUSERSPROFILE%\chocolatey\bin
choco upgrade -y chocolatey
call refreshenv && echo OK

REM Install system tools
Dism /online /Enable-Feature /FeatureName:"NetFx3" && choco install -y --no-progress pathed
choco install -y --no-progress nsis
REM choco install -y --no-progress zip
REM choco install -y --no-progress unzip
REM choco install -y --no-progress curl
call refreshenv && echo OK

REM Install CI-specific dependencies and tools
if DEFINED MINIMAL_INSTALL goto :cispecificdeps_end
choco install -y --no-progress jre8
choco install -y --no-progress notepadplusplus
choco install -y --no-progress vswhere
call refreshenv && echo OK
:cispecificdeps_end


REM Install SOFA dependencies with Chocolatey
choco install -y --no-progress git --version=2.25.1
pathed /MACHINE /APPEND "C:\Program Files\Git\bin"
choco install -y --no-progress wget --version=1.20.3.20190531
choco install -y --no-progress ninja --version=1.10.0
choco install -y --no-progress cmake --version=3.16.2 --installargs 'ADD_CMAKE_TO_PATH=System'
choco install -y --no-progress python --version=3.8.10
call refreshenv && echo OK
python -m pip install --upgrade pip
python -m pip install numpy scipy


REM Install plugins dependencies
if DEFINED MINIMAL_INSTALL goto :plugindeps_end
choco install -y --no-progress cuda --version=10.2.89.20191206
REM Bullet: source code to build: https://github.com/bulletphysics/bullet3/releases
:plugindeps_end

REM Install clcache
if exist C:\clcache goto :clcache_end
echo Installing Clcache...
set CLCACHE_MAJOR=4
set CLCACHE_MINOR=2
set CLCACHE_PATCH=0
powershell -Command "Invoke-WebRequest "^
    "https://github.com/frerich/clcache/releases/download/"^
        "v%CLCACHE_MAJOR%.%CLCACHE_MINOR%.%CLCACHE_PATCH%/clcache-%CLCACHE_MAJOR%.%CLCACHE_MINOR%.%CLCACHE_PATCH%.zip "^
    "-OutFile %WORKDIR%\clcache.zip"
powershell Expand-Archive %WORKDIR%\clcache.zip -DestinationPath C:\clcache
REM if not exist "J:\clcache\" mkdir "J:\clcache"
REM setx /M CLCACHE_OBJECT_CACHE_TIMEOUT_MS 3600000
REM setx /M CLCACHE_DIR J:\clcache
REM setx /M CLCACHE_BASEDIR J:\workspace
REM (
  REM echo {
  REM echo "MaximumCacheSize": 34359738368
  REM echo }
REM ) > J:\clcache\config.txt
pathed /MACHINE /APPEND "C:\clcache"
:clcache_end


REM Install Visual Studio Build Tools 2017
if exist C:\VSBuildTools goto :vs_end
echo Installing Visual Studio Build Tools...
REM To see component names, run Visual Studio Installer and play with configuration export.
REM Use --passive instead of --quiet when testing (GUI will appear with progress bar).
powershell -Command "Invoke-WebRequest "^
    "https://aka.ms/vs/15/release/vs_buildtools.exe "^
    "-OutFile %WORKDIR%\vs_buildtools.exe"
%WORKDIR%\vs_buildtools.exe ^
    --wait --quiet --norestart --nocache ^
    --installPath C:\VSBuildTools ^
    --add Microsoft.VisualStudio.Workload.VCTools ^
    --add microsoft.visualstudio.component.vc.cmake.project ^
    --add microsoft.visualstudio.component.testtools.buildtools ^
    --add microsoft.visualstudio.component.vc.atlmfc ^
    --add microsoft.visualstudio.component.vc.cli.support ^
    --includeRecommended ^
   & call %SCRIPTDIR%\wait_process_to_end.bat "vs_bootstrapper.exe" ^
   & call %SCRIPTDIR%\wait_process_to_end.bat "vs_BuildTools.exe" ^
   & call %SCRIPTDIR%\wait_process_to_end.bat "vs_buildtools.exe" ^
   & call %SCRIPTDIR%\wait_process_to_end.bat "vs_installer.exe"

setx /M VS150COMNTOOLS C:\VSBuildTools\Common7\Tools\
setx /M VSINSTALLDIR C:\VSBuildTools\
:vs_end


REM Install Qt
if exist C:\Qt goto :qt_end
echo Installing Qt...
set QT_MAJOR=5
set QT_MINOR=12
set QT_PATCH=6
python -m pip install aqtinstall
python -m aqt install-qt   --outputdir C:\Qt windows desktop %QT_MAJOR%.%QT_MINOR%.%QT_PATCH% win64_msvc2017_64 -m qtcharts qtwebengine
python -m aqt install-tool --outputdir C:\Qt windows desktop tools_ifw
:qt_end


REM Install Boost
if exist C:\boost goto :boost_end
echo Installing Boost...
set BOOST_MAJOR=1
set BOOST_MINOR=69
set BOOST_PATCH=0
powershell -Command "Invoke-WebRequest "^
    "https://boost.teeks99.com/bin/%BOOST_MAJOR%.%BOOST_MINOR%.%BOOST_PATCH%/boost_%BOOST_MAJOR%_%BOOST_MINOR%_%BOOST_PATCH%-msvc-14.1-64.exe "^
    "-OutFile %WORKDIR%\boostinstaller.exe"
%WORKDIR%\boostinstaller.exe /NORESTART /VERYSILENT /DIR=C:\boost
call %SCRIPTDIR%\wait_process_to_end.bat "boostinstaller.exe"
:boost_end


REM Install Eigen
if exist C:\eigen goto :eigen_end
echo Installing Eigen...
set EIGEN_MAJOR=3
set EIGEN_MINOR=3
set EIGEN_PATCH=7
powershell -Command "Invoke-WebRequest "^
    "https://gitlab.com/libeigen/eigen/-/archive/%EIGEN_MAJOR%.%EIGEN_MINOR%.%EIGEN_PATCH%/eigen-%EIGEN_MAJOR%.%EIGEN_MINOR%.%EIGEN_PATCH%.zip "^
    "-OutFile %WORKDIR%\eigen.zip"
powershell Expand-Archive %WORKDIR%\eigen.zip -DestinationPath C:\eigen
:eigen_end


REM Install Assimp
if DEFINED MINIMAL_INSTALL goto :assimp_end
if exist C:\assimp goto :assimp_end
echo Installing Assimp...
set ASSIMP_MAJOR=4
set ASSIMP_MINOR=1
set ASSIMP_PATCH=0
powershell -Command "Invoke-WebRequest "^
    "https://github.com/assimp/assimp/releases/download/"^
        "v%ASSIMP_MAJOR%.%ASSIMP_MINOR%.%ASSIMP_PATCH%/assimp-sdk-%ASSIMP_MAJOR%.%ASSIMP_MINOR%.%ASSIMP_PATCH%-setup.exe "^
    "-OutFile %WORKDIR%\assimpinstaller.exe"
%WORKDIR%\assimpinstaller.exe /NORESTART /VERYSILENT /DIR=C:\assimp
call %SCRIPTDIR%\wait_process_to_start.bat "vc_redist.x64.exe"
taskkill /F /IM vc_redist.x64.exe
call %SCRIPTDIR%\wait_process_to_end.bat "assimpinstaller.exe"
pathed /MACHINE /APPEND "C:\assimp"
:assimp_end


REM Install CGAL
if DEFINED MINIMAL_INSTALL goto :cgal_end
if exist C:\CGAL goto :cgal_end
echo Installing CGAL...
set CGAL_MAJOR=5
set CGAL_MINOR=0
set CGAL_PATCH=2
powershell -Command "Invoke-WebRequest "^
    "https://github.com/CGAL/cgal/releases/download/releases/CGAL-%CGAL_MAJOR%.%CGAL_MINOR%.%CGAL_PATCH%/CGAL-%CGAL_MAJOR%.%CGAL_MINOR%.%CGAL_PATCH%-Setup.exe "^
    "-OutFile %WORKDIR%\cgalinstaller.exe"
%WORKDIR%\cgalinstaller.exe /S /D=C:\CGAL
call %SCRIPTDIR%\wait_process_to_end.bat "cgalinstaller.exe"
pathed /MACHINE /APPEND "C:\CGAL"
:cgal_end


REM Install OpenCascade
if DEFINED MINIMAL_INSTALL goto :occ_end
if exist C:\OpenCascade goto :occ_end
echo Installing OpenCascade...
set OCC_MAJOR=7
set OCC_MINOR=4
set OCC_PATCH=0
powershell -Command "Invoke-WebRequest "^
    "http://transfer.sofa-framework.org/opencascade-%OCC_MAJOR%.%OCC_MINOR%.%OCC_PATCH%-vc14-64.exe "^
    "-OutFile %WORKDIR%\occinstaller.exe"
%WORKDIR%\occinstaller.exe /NORESTART /VERYSILENT /DIR=C:\OpenCascade
call %SCRIPTDIR%\wait_process_to_end.bat "occinstaller.exe"
pathed /MACHINE /APPEND "C:\OpenCascade\opencascade-%OCC_MAJOR%.%OCC_MINOR%.%OCC_PATCH%"
:occ_end


REM Install pybind11
if DEFINED MINIMAL_INSTALL goto :pybind11_end
if exist C:\pybind11 goto :pybind11_end
echo Installing pybind11...
set PYBIND11_MAJOR=2
set PYBIND11_MINOR=4
set PYBIND11_PATCH=2
set PYBIND11_ROOT=C:\pybind11\%PYBIND11_MAJOR%.%PYBIND11_MINOR%.%PYBIND11_PATCH%
powershell -Command "Invoke-WebRequest "^
    "https://github.com/pybind/pybind11/archive/refs/tags/v%PYBIND11_MAJOR%.%PYBIND11_MINOR%.%PYBIND11_PATCH%.zip "^
    "-OutFile %WORKDIR%\pybind11.zip"
powershell Expand-Archive %WORKDIR%\pybind11.zip -DestinationPath %PYBIND11_ROOT%
move %PYBIND11_ROOT%\pybind11-%PYBIND11_MAJOR%.%PYBIND11_MINOR%.%PYBIND11_PATCH% %PYBIND11_ROOT%\src
mkdir %PYBIND11_ROOT%\build && cd %PYBIND11_ROOT%\build
%VS150COMNTOOLS%\VsDevCmd -host_arch=amd64 -arch=amd64 ^
    && cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=%PYBIND11_ROOT%\install -DPYBIND11_TEST=OFF ..\src ^
    && ninja install
pathed /MACHINE /APPEND "%PYBIND11_ROOT%\install"
setx /M pybind11_ROOT %PYBIND11_ROOT%\install
:pybind11_end


REM Install ZeroMQ
if DEFINED MINIMAL_INSTALL goto :zmq_end
if exist C:\zeromq goto :zmq_end
echo Installing ZMQ...
set ZMQ_MAJOR=4
set ZMQ_MINOR=3
set ZMQ_PATCH=2
set ZMQ_ROOT=C:\zeromq\%ZMQ_MAJOR%.%ZMQ_MINOR%.%ZMQ_PATCH%
powershell -Command "Invoke-WebRequest "^
    "https://github.com/zeromq/libzmq/releases/download/v%ZMQ_MAJOR%.%ZMQ_MINOR%.%ZMQ_PATCH%/zeromq-%ZMQ_MAJOR%.%ZMQ_MINOR%.%ZMQ_PATCH%.zip "^
    "-OutFile %WORKDIR%\zmq.zip"
powershell Expand-Archive %WORKDIR%\zmq.zip -DestinationPath %ZMQ_ROOT%
move %ZMQ_ROOT%\zeromq-%ZMQ_MAJOR%.%ZMQ_MINOR%.%ZMQ_PATCH% %ZMQ_ROOT%\src
mkdir %ZMQ_ROOT%\build && cd %ZMQ_ROOT%\build
%VS150COMNTOOLS%\VsDevCmd -host_arch=amd64 -arch=amd64 ^
    && cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=%ZMQ_ROOT%\install -DBUILD_STATIC=OFF ..\src ^
    && ninja install
powershell -Command "Invoke-WebRequest "^
    "https://raw.githubusercontent.com/zeromq/cppzmq/master/zmq.hpp "^
    "-OutFile %ZMQ_ROOT%\install\include\zmq.hpp"
powershell -Command "Invoke-WebRequest "^
    "https://raw.githubusercontent.com/zeromq/cppzmq/master/zmq_addon.hpp "^
    "-OutFile %ZMQ_ROOT%\install\include\zmq_addon.hpp"
pathed /MACHINE /APPEND "%ZMQ_ROOT%\install"
setx /M ZMQ_ROOT %ZMQ_ROOT%\install
:zmq_end


REM Install VRPN
if DEFINED MINIMAL_INSTALL goto :vrpn_end
if exist C:\vrpn goto :vrpn_end
echo Installing VRPN...
set VRPN_MAJOR=07
set VRPN_MINOR=33
set VRPN_ROOT=C:\vrpn\%VRPN_MAJOR%.%VRPN_MINOR%
powershell -Command "Invoke-WebRequest "^
    "https://github.com/vrpn/vrpn/releases/download/v%VRPN_MAJOR%.%VRPN_MINOR%/vrpn_%VRPN_MAJOR%_%VRPN_MINOR%.zip "^
    "-OutFile %WORKDIR%\vrpn.zip"
powershell Expand-Archive %WORKDIR%\vrpn.zip -DestinationPath %VRPN_ROOT%
move %VRPN_ROOT%\vrpn %VRPN_ROOT%\src
mkdir %VRPN_ROOT%\build && cd %VRPN_ROOT%\build
%VS150COMNTOOLS%\VsDevCmd -host_arch=amd64 -arch=amd64 ^
    && cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=%VRPN_ROOT%\install ..\src ^
    && ninja install
pathed /MACHINE /APPEND "%VRPN_ROOT%\install"
setx /M VRPN_ROOT %VRPN_ROOT%\install
:vrpn_end


REM Install Oscpack
if DEFINED MINIMAL_INSTALL goto :oscpack_end
if exist C:\oscpack goto :oscpack_end
echo Installing OSC...
set OSC_MAJOR=1
set OSC_MINOR=1
set OSC_PATCH=0
set OSC_ROOT=C:\oscpack\%OSC_MAJOR%.%OSC_MINOR%.%OSC_PATCH%
powershell -Command "Invoke-WebRequest "^
    "https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/oscpack/oscpack_%OSC_MAJOR%_%OSC_MINOR%_%OSC_PATCH%.zip "^
    "-OutFile %WORKDIR%\oscpack.zip"
powershell Expand-Archive %WORKDIR%\oscpack.zip -DestinationPath %OSC_ROOT%
move %OSC_ROOT%\oscpack_%OSC_MAJOR%_%OSC_MINOR%_%OSC_PATCH% %OSC_ROOT%\src
mkdir %OSC_ROOT%\build && cd %OSC_ROOT%\build
%VS150COMNTOOLS%\VsDevCmd -host_arch=amd64 -arch=amd64 ^
    && cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=%OSC_ROOT%\install ..\src ^
    && ninja
Xcopy /E /I %OSC_ROOT%\src\ip %OSC_ROOT%\install\include\oscpack\ip\
Xcopy /E /I %OSC_ROOT%\src\osc %OSC_ROOT%\install\include\oscpack\osc\
Xcopy /E /I %OSC_ROOT%\build\oscpack.lib %OSC_ROOT%\install\lib\
pathed /MACHINE /APPEND "%OSC_ROOT%\install"
setx /M Oscpack_ROOT %OSC_ROOT%\install
:oscpack_end


REM Finalize environment
echo Finalizing environment...
call refreshenv && echo OK
setx /M PYTHONIOENCODING UTF-8
REM Strip duplicate PATH vars
pathed /MACHINE /SLIM

echo Done
