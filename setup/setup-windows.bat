@echo off

set WORKDIR=%TEMP%\%~n0
rmdir /S /Q %WORKDIR%
mkdir %WORKDIR%

REM Install Chocolatey (will also install refreshenv command)
powershell -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))"
set AddToUserPATH=%ALLUSERSPROFILE%\chocolatey\bin


REM Install CI specific dependencies
choco install -y jre8
choco install -y notepadplusplus
choco install -y vswhere
Dism /online /Enable-Feature /FeatureName:"NetFx3" && choco install -y pathed
REM choco install -y zip
REM choco install -y unzip
REM choco install -y curl
call refreshenv && echo OK


REM Install SOFA dependencies with Chocolatey
choco install -y git --version=2.25.1
pathed /MACHINE /APPEND "C:\Program Files\Git\bin"
choco install -y wget --version=1.20.3.20190531
choco install -y ninja --version=1.10.0
choco install -y cmake --version=3.16.2 --installargs 'ADD_CMAKE_TO_PATH=System'
choco install -y python2 --version=2.7.17
call refreshenv && echo OK
python -m pip install --upgrade pip
python -m pip install numpy scipy


REM Install plugins dependencies
choco install -y cuda --version=10.2.89.20191206
REM Bullet: source code to build: https://github.com/bulletphysics/bullet3/releases
REM Pybind: source code to build: https://github.com/pybind/pybind11/releases


REM Install clcache
if exist C:\clcache goto :clcache_done
echo Installing Clcache...
powershell -Command "Invoke-WebRequest https://github.com/frerich/clcache/releases/download/v4.2.0/clcache-4.2.0.zip -OutFile %WORKDIR%\clcache.zip"
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
:clcache_done


REM Install Visual Studio Build Tools 2017
if exist C:\VSBuildTools goto :vs_done
echo Installing Visual Studio Build Tools...
REM To see component names, run Visual Studio Installer and play with configuration export.
REM Use --passive instead of --quiet when testing (GUI will appear with progress bar).
powershell -Command "Invoke-WebRequest https://raw.githubusercontent.com/sofa-framework/ci/master/setup/wait_process_to_end.bat -OutFile %WORKDIR%\wait_process_to_end.bat"
powershell -Command "Invoke-WebRequest https://aka.ms/vs/15/release/vs_buildtools.exe -OutFile %WORKDIR%\vs_buildtools.exe"
%WORKDIR%\vs_buildtools.exe ^
    --wait --quiet --norestart --nocache ^
    --installPath C:\VSBuildTools ^
    --add Microsoft.VisualStudio.Workload.VCTools ^
    --add microsoft.visualstudio.component.vc.cmake.project ^
    --add microsoft.visualstudio.component.testtools.buildtools ^
    --add microsoft.visualstudio.component.vc.atlmfc ^
    --add microsoft.visualstudio.component.vc.cli.support ^
    --includeRecommended ^
   & call %WORKDIR%\wait_process_to_end.bat "vs_bootstrapper.exe" ^
   & call %WORKDIR%\wait_process_to_end.bat "vs_BuildTools.exe" ^
   & call %WORKDIR%\wait_process_to_end.bat "vs_buildtools.exe" ^
   & call %WORKDIR%\wait_process_to_end.bat "vs_installer.exe"

setx /M VS150COMNTOOLS C:\VSBuildTools\Common7\Tools\
setx /M VSINSTALLDIR C:\VSBuildTools\
:vs_done


REM Install Qt
if exist C:\Qt goto :qt_done
echo Installing Qt...
set QT_MAJOR=5
set QT_MINOR=12
set QT_PATCH=6
REM setx /M QTDIR "C:\Qt\%QT_MAJOR%.%QT_MINOR%.%QT_PATCH%\msvc2017_64"
REM setx /M QTDIR64 %QTDIR%
REM setx /M Qt5_DIR %QTDIR%
if not exist "%APPDATA%\Qt\" mkdir %APPDATA%\Qt
powershell -Command "Invoke-WebRequest https://raw.githubusercontent.com/sofa-framework/ci/master/setup/qtaccount.ini -OutFile %APPDATA%\Qt\qtaccount.ini"
powershell -Command "Invoke-WebRequest https://raw.githubusercontent.com/sofa-framework/ci/master/setup/qtinstaller_controlscript_template.qs -OutFile %WORKDIR%\qtinstaller_controlscript_template.qs"
powershell -Command "(gc %WORKDIR%\qtinstaller_controlscript_template.qs) -replace '_QTVERSION_', %QT_MAJOR%%QT_MINOR%%QT_PATCH% | Out-File -encoding ASCII %WORKDIR%\qtinstaller_controlscript.qs"
powershell -Command "Invoke-WebRequest https://download.qt.io/official_releases/online_installers/qt-unified-windows-x86-online.exe -OutFile %WORKDIR%\qtinstaller.exe"
%WORKDIR%\qtinstaller.exe --script %WORKDIR%\qtinstaller_controlscript.qs
:qt_done


REM Install Boost
if exist C:\boost goto :boost_done
echo Installing Boost...
set BOOST_MAJOR=1
set BOOST_MINOR=69
set BOOST_PATCH=0
powershell -Command "Invoke-WebRequest https://raw.githubusercontent.com/sofa-framework/ci/master/setup/wait_process_to_end.bat -OutFile %WORKDIR%\wait_process_to_end.bat"
powershell -Command "Invoke-WebRequest https://boost.teeks99.com/bin/%BOOST_MAJOR%.%BOOST_MINOR%.%BOOST_PATCH%/boost_%BOOST_MAJOR%_%BOOST_MINOR%_%BOOST_PATCH%-msvc-14.1-64.exe -OutFile %WORKDIR%\boostinstaller.exe"
%WORKDIR%\boostinstaller.exe /NORESTART /VERYSILENT /DIR=C:\boost
call %WORKDIR%\wait_process_to_end.bat "boostinstaller.exe"
:boost_done


REM Install Eigen
if exist C:\eigen\eigen-3.3.7 goto :eigen_done
powershell -Command "Invoke-WebRequest https://gitlab.com/libeigen/eigen/-/archive/3.3.7/eigen-3.3.7.zip -OutFile %WORKDIR%\eigen.zip"
powershell Expand-Archive %WORKDIR%\eigen.zip -DestinationPath C:\eigen
:eigen_done


REM Install Assimp
if exist C:\assimp goto :assimp_done
echo Installing Assimp...
set ASSIMP_MAJOR=4
set ASSIMP_MINOR=1
set ASSIMP_PATCH=0
powershell -Command "Invoke-WebRequest https://raw.githubusercontent.com/sofa-framework/ci/master/setup/wait_process_to_start.bat -OutFile %WORKDIR%\wait_process_to_start.bat"
powershell -Command "Invoke-WebRequest https://raw.githubusercontent.com/sofa-framework/ci/master/setup/wait_process_to_end.bat -OutFile %WORKDIR%\wait_process_to_end.bat"
powershell -Command "Invoke-WebRequest https://github.com/assimp/assimp/releases/download/v%ASSIMP_MAJOR%.%ASSIMP_MINOR%.%ASSIMP_PATCH%/assimp-sdk-%ASSIMP_MAJOR%.%ASSIMP_MINOR%.%ASSIMP_PATCH%-setup.exe -OutFile %WORKDIR%\assimpinstaller.exe"
%WORKDIR%\assimpinstaller.exe /NORESTART /VERYSILENT /DIR=C:\assimp
call %WORKDIR%\wait_process_to_start.bat "vc_redist.x64.exe"
taskkill /F /IM vc_redist.x64.exe
call %WORKDIR%\wait_process_to_end.bat "assimpinstaller.exe"
pathed /MACHINE /APPEND "C:\assimp"
:assimp_done


REM Install CGAL
if exist C:\CGAL goto :cgal_done
echo Installing CGAL...
set CGAL_MAJOR=5
set CGAL_MINOR=0
set CGAL_PATCH=2
powershell -Command "Invoke-WebRequest https://raw.githubusercontent.com/sofa-framework/ci/master/setup/wait_process_to_end.bat -OutFile %WORKDIR%\wait_process_to_end.bat"
powershell -Command "Invoke-WebRequest https://github.com/CGAL/cgal/releases/download/releases/CGAL-%CGAL_MAJOR%.%CGAL_MINOR%.%CGAL_PATCH%/CGAL-%CGAL_MAJOR%.%CGAL_MINOR%.%CGAL_PATCH%-Setup.exe -OutFile %WORKDIR%\cgalinstaller.exe"
%WORKDIR%\cgalinstaller.exe /S /D=C:\CGAL
call %WORKDIR%\wait_process_to_end.bat "cgalinstaller.exe"
pathed /MACHINE /APPEND "C:\CGAL"
:cgal_done


REM Install OpenCascade
if exist C:\OpenCascade goto :occ_done
echo Installing OpenCascade...
set OCC_MAJOR=7
set OCC_MINOR=4
set OCC_PATCH=0
powershell -Command "Invoke-WebRequest https://raw.githubusercontent.com/sofa-framework/ci/master/setup/wait_process_to_end.bat -OutFile %WORKDIR%\wait_process_to_end.bat"
powershell -Command "Invoke-WebRequest http://transfer.sofa-framework.org/opencascade-%OCC_MAJOR%.%OCC_MINOR%.%OCC_PATCH%-vc14-64.exe -OutFile %WORKDIR%\occinstaller.exe"
%WORKDIR%\occinstaller.exe /NORESTART /VERYSILENT /DIR=C:\OpenCascade
call %WORKDIR%\wait_process_to_end.bat "occinstaller.exe"
pathed /MACHINE /APPEND "C:\OpenCascade\opencascade-%OCC_MAJOR%.%OCC_MINOR%.%OCC_PATCH%"
:occ_done


REM Finalize environment
echo Finalizing environment...
call refreshenv && echo OK
setx /M PYTHONIOENCODING UTF-8
REM Strip duplicate PATH vars
pathed /MACHINE /SLIM

echo Done
