@echo off

REM Install is MINIMAL by default
REM Add "FULL" argument to enable FULL install
set MINIMAL_INSTALL="TRUE"
if "%1" == "FULL" set "MINIMAL_INSTALL="

set SCRIPTDIR=%~dp0
set WORKDIR=%TEMP%\%~n0
rmdir /S /Q %WORKDIR%
mkdir %WORKDIR%

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
choco install -y --no-progress git --version=2.34.1
pathed /MACHINE /APPEND "C:\Program Files\Git\bin"
choco install -y --no-progress wget --version=1.21.2
choco install -y --no-progress ninja --version=1.10.1
choco install -y --no-progress cmake --version=3.22.1 --installargs 'ADD_CMAKE_TO_PATH=System'
choco install -y --no-progress python --version=3.10.11
call refreshenv && echo OK
pathed /MACHINE /REMOVE C:\Python310\Scripts\
pathed /MACHINE /REMOVE C:\Python310\
C:\Python310\python.exe -m pip install --upgrade pip
C:\Python310\python.exe -m pip install numpy scipy pybind11==2.9.1 matplotlib


REM Install plugins dependencies
if DEFINED MINIMAL_INSTALL goto :plugindeps_end
choco install -y --no-progress cuda
REM Bullet: source code to build: https://github.com/bulletphysics/bullet3/releases
:plugindeps_end

REM Install clcache
if exist C:\clcache goto :clcache_end
echo Installing Clcache...
set CLCACHE_MAJOR=4
set CLCACHE_MINOR=2
set CLCACHE_PATCH=0
powershell -Command "Invoke-WebRequest "^
    "https://github.com/frerich/clcache/releases/download/v%CLCACHE_MAJOR%.%CLCACHE_MINOR%.%CLCACHE_PATCH%/clcache-%CLCACHE_MAJOR%.%CLCACHE_MINOR%.%CLCACHE_PATCH%.zip "^
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


REM Install Visual Studio Build Tools VS2022
if exist C:\VSBuildTools\VS2022 goto :vs22_end
echo Installing Visual Studio Build Tools...
REM To see component names, run Visual Studio Installer and play with configuration export.
REM Use --passive instead of --quiet when testing (GUI will appear with progress bar).
powershell -Command "Invoke-WebRequest "^
    "https://aka.ms/vs/17/release/vs_buildtools.exe "^
    "-OutFile %WORKDIR%\vs_buildtools.exe"
%WORKDIR%\vs_buildtools.exe ^
    --wait --quiet --norestart --nocache ^
    --installPath C:\VSBuildTools\VS2022 ^
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

setx /M VS170COMNTOOLS C:\VSBuildTools\VS2022\Common7\Tools\
setx /M VSINSTALLDIR C:\VSBuildTools\VS2022\
:vs22_end


REM Install Qt
if exist C:\Qt goto :qt_end
echo Installing Qt...
set QT_MAJOR=5
set QT_MINOR=12
set QT_PATCH=12
C:\Python310\python.exe -m pip install aqtinstall
C:\Python310\python.exe -m aqt install-qt   --outputdir C:\Qt windows desktop %QT_MAJOR%.%QT_MINOR%.%QT_PATCH% win64_msvc2017_64 -m qtcharts qtwebengine
C:\Python310\python.exe -m aqt install-tool --outputdir C:\Qt windows desktop tools_ifw qt.tools.ifw.43
setx /M QTIFWDIR C:\Qt\Tools\QtInstallerFramework\4.3
:qt_end


REM Install Boost
if exist C:\boost goto :boost_end
echo Installing Boost...
set BOOST_MAJOR=1
set BOOST_MINOR=74
set BOOST_PATCH=0
powershell -Command "Invoke-WebRequest "^
    "https://sourceforge.net/projects/boost/files/boost-binaries/%BOOST_MAJOR%.%BOOST_MINOR%.%BOOST_PATCH%/boost_%BOOST_MAJOR%_%BOOST_MINOR%_%BOOST_PATCH%-msvc-14.2-64.exe "^
    "-OutFile %WORKDIR%\boostinstaller.exe "^
    "-UserAgent [Microsoft.PowerShell.Commands.PSUserAgent]::FireFox"
%WORKDIR%\boostinstaller.exe /NORESTART /VERYSILENT /DIR=C:\boost
call %SCRIPTDIR%\wait_process_to_end.bat "boostinstaller.exe"
:boost_end


REM Install Eigen
if exist C:\eigen goto :eigen_end
echo Installing Eigen...
set EIGEN_MAJOR=3
set EIGEN_MINOR=4
set EIGEN_PATCH=0
powershell -Command "Invoke-WebRequest "^
    "https://gitlab.com/libeigen/eigen/-/archive/%EIGEN_MAJOR%.%EIGEN_MINOR%.%EIGEN_PATCH%/eigen-%EIGEN_MAJOR%.%EIGEN_MINOR%.%EIGEN_PATCH%.zip "^
    "-OutFile %WORKDIR%\eigen.zip"
powershell Expand-Archive %WORKDIR%\eigen.zip -DestinationPath C:\eigen
:eigen_end


echo Done
