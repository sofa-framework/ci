@echo off

REM Install is MINIMAL by default
REM Add "FULL" argument to enable FULL install
set MINIMAL_INSTALL="TRUE"
if "%1" == "FULL" set "MINIMAL_INSTALL="

set SCRIPTDIR=%~dp0
set WORKDIR=%TEMP%\%~n0
rmdir /S /Q %WORKDIR%
mkdir %WORKDIR%



REM Install Assimp
if DEFINED MINIMAL_INSTALL goto :assimp_end
if exist C:\assimp goto :assimp_end
echo Installing Assimp...
set ASSIMP_MAJOR=5
set ASSIMP_MINOR=2
set ASSIMP_PATCH=2
set ASSIMP_ROOT=C:\assimp\%ASSIMP_MAJOR%.%ASSIMP_MINOR%.%ASSIMP_PATCH%
powershell -Command "Invoke-WebRequest "^
    "https://github.com/assimp/assimp/archive/refs/tags/v%ASSIMP_MAJOR%.%ASSIMP_MINOR%.%ASSIMP_PATCH%.zip "^
    "-OutFile %WORKDIR%\assimp.zip"
powershell Expand-Archive %WORKDIR%\assimp.zip -DestinationPath %ASSIMP_ROOT%
move %ASSIMP_ROOT%\assimp-%ASSIMP_MAJOR%.%ASSIMP_MINOR%.%ASSIMP_PATCH% %ASSIMP_ROOT%\src
mkdir %ASSIMP_ROOT%\build && cd %ASSIMP_ROOT%\build
call %VS170COMNTOOLS%\VsDevCmd -host_arch=amd64 -arch=amd64 ^
    && cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=%ASSIMP_ROOT%\install -DBUILD_STATIC=OFF ..\src ^
    && ninja install
pathed /MACHINE /APPEND "%ASSIMP_ROOT%\install"
pathed /MACHINE /APPEND "%ASSIMP_ROOT%\install\bin"
setx /M ASSIMP_ROOT %ASSIMP_ROOT%\install
RMDIR /S /Q "%ASSIMP_ROOT%\src"
RMDIR /S /Q "%ASSIMP_ROOT%\build"
:assimp_end


REM Install CGAL
if DEFINED MINIMAL_INSTALL goto :cgal_end
if exist C:\CGAL goto :cgal_end
echo Installing CGAL...
set CGAL_MAJOR=5
set CGAL_MINOR=4
set CGAL_PATCH=1
set CGAL_ROOT=C:\cgal\%CGAL_MAJOR%.%CGAL_MINOR%.%CGAL_PATCH%
powershell -Command "Invoke-WebRequest "^
    "https://github.com/CGAL/cgal/releases/download/v%CGAL_MAJOR%.%CGAL_MINOR%.%CGAL_PATCH%/CGAL-%CGAL_MAJOR%.%CGAL_MINOR%.%CGAL_PATCH%.zip "^
    "-OutFile %WORKDIR%\cgal.zip"
powershell Expand-Archive %WORKDIR%\cgal.zip -DestinationPath %CGAL_ROOT%
move %CGAL_ROOT%\CGAL-%CGAL_MAJOR%.%CGAL_MINOR%.%CGAL_PATCH% %CGAL_ROOT%\src
mkdir %CGAL_ROOT%\build && cd %CGAL_ROOT%\build
call %VS170COMNTOOLS%\VsDevCmd -host_arch=amd64 -arch=amd64 ^
    && cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=%CGAL_ROOT%\install -DBUILD_STATIC=OFF ..\src ^
    && ninja install
pathed /MACHINE /APPEND "%CGAL_ROOT%\install"
pathed /MACHINE /APPEND "%CGAL_ROOT%\install\bin"
setx /M CGAL_ROOT %CGAL_ROOT%\install
RMDIR /S /Q "%CGAL_ROOT%\src"
RMDIR /S /Q "%CGAL_ROOT%\build"
:cgal_end




REM Install ZeroMQ
if DEFINED MINIMAL_INSTALL goto :zmq_end
if exist C:\zeromq goto :zmq_end
echo Installing ZMQ...
set ZMQ_MAJOR=4
set ZMQ_MINOR=3
set ZMQ_PATCH=4
set ZMQ_ROOT=C:\zeromq\%ZMQ_MAJOR%.%ZMQ_MINOR%.%ZMQ_PATCH%
powershell -Command "Invoke-WebRequest "^
    "https://github.com/zeromq/libzmq/releases/download/v%ZMQ_MAJOR%.%ZMQ_MINOR%.%ZMQ_PATCH%/zeromq-%ZMQ_MAJOR%.%ZMQ_MINOR%.%ZMQ_PATCH%.zip "^
    "-OutFile %WORKDIR%\zmq.zip"
powershell Expand-Archive %WORKDIR%\zmq.zip -DestinationPath %ZMQ_ROOT%
move %ZMQ_ROOT%\zeromq-%ZMQ_MAJOR%.%ZMQ_MINOR%.%ZMQ_PATCH% %ZMQ_ROOT%\src
mkdir %ZMQ_ROOT%\build && cd %ZMQ_ROOT%\build
call %VS170COMNTOOLS%\VsDevCmd -host_arch=amd64 -arch=amd64 ^
    && cmake -GNinja -DCMAKE_BUILD_TYPE=Release  -DBUILD_STATIC=OFF ..\src ^
    && ninja install
	REM -DCMAKE_INSTALL_PREFIX=%ZMQ_ROOT%\install
REM powershell -Command "Invoke-WebRequest "^
    REM "https://raw.githubusercontent.com/zeromq/cppzmq/master/zmq.hpp "^
    REM "-OutFile %ZMQ_ROOT%\install\include\zmq.hpp"
REM powershell -Command "Invoke-WebRequest "^
    REM "https://raw.githubusercontent.com/zeromq/cppzmq/master/zmq_addon.hpp "^
    REM "-OutFile %ZMQ_ROOT%\install\include\zmq_addon.hpp"
pathed /MACHINE /APPEND "C:\Program Files (x86)\ZeroMQ"
pathed /MACHINE /APPEND "C:\Program Files (x86)\ZeroMQ\bin"
setx /M ZMQ_ROOT "C:\Program Files (x86)\ZeroMQ"
RMDIR /S /Q "%ZMQ_ROOT%\src" 
RMDIR /S /Q "%ZMQ_ROOT%\build" 
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
call %VS170COMNTOOLS%\VsDevCmd -host_arch=amd64 -arch=amd64 ^
    && cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=%VRPN_ROOT%\install ..\src ^
    && ninja install 

pathed /MACHINE /APPEND "%VRPN_ROOT%\install"
pathed /MACHINE /APPEND "%VRPN_ROOT%\install\bin"
setx /M VRPN_ROOT %VRPN_ROOT%\install
RMDIR /S /Q "%VRPN_ROOT%\src" 
RMDIR /S /Q "%VRPN_ROOT%\build" 
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
call %VS170COMNTOOLS%\VsDevCmd -host_arch=amd64 -arch=amd64 ^
    && cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=%OSC_ROOT%\install ..\src ^
    && ninja
Xcopy /E /I %OSC_ROOT%\src\ip %OSC_ROOT%\install\include\oscpack\ip\
Xcopy /E /I %OSC_ROOT%\src\osc %OSC_ROOT%\install\include\oscpack\osc\
Xcopy /E /I %OSC_ROOT%\build\oscpack.lib %OSC_ROOT%\install\lib\
pathed /MACHINE /APPEND "%OSC_ROOT%\install"
pathed /MACHINE /APPEND "%OSC_ROOT%\install\bin"
setx /M Oscpack_ROOT %OSC_ROOT%\install
RMDIR /S /Q "%OSC_ROOT%\src" 
RMDIR /S /Q "%OSC_ROOT%\build" 
:oscpack_end


REM Install METIS
if DEFINED MINIMAL_INSTALL goto :metis_end
if exist C:\METIS goto :metis_end
echo Installing METIS...
set METIS_MAJOR=5
set METIS_MINOR=2
set METIS_PATCH=1
set METIS_ROOT=C:\METIS\%METIS_MAJOR%.%METIS_MINOR%.%METIS_PATCH%
mkdir C:\METIS
mkdir %METIS_ROOT% && cd %METIS_ROOT%
call git clone https://github.com/sofa-framework/METIS.git
move METIS src && cd src
call git checkout v5.2.1-ModernInstall
mkdir %METIS_ROOT%\install
mkdir %METIS_ROOT%\build && cd %METIS_ROOT%\build
call %VS170COMNTOOLS%\VsDevCmd -host_arch=amd64 -arch=amd64 ^
    && cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=%METIS_ROOT%\install ..\src ^
    && ninja install



pathed /MACHINE /APPEND "%METIS_ROOT%\install"
pathed /MACHINE /APPEND "%METIS_ROOT%\install\bin"
setx /M METIS_ROOT %METIS_ROOT%\install
RMDIR /S /Q "%METIS_ROOT%\src" 
RMDIR /S /Q "%METIS_ROOT%\build" 
:metis_end


REM Install TINYXML2
if DEFINED MINIMAL_INSTALL goto :tinyxml2_end
if exist C:\TINYXML2 goto :tinyxml2_end
echo Installing TINYXML2...
set TINYXML2_MAJOR=9
set TINYXML2_MINOR=0
set TINYXML2_PATCH=0
set TINYXML2_ROOT=C:\TINYXML2\%TINYXML2_MAJOR%.%TINYXML2_MINOR%.%TINYXML2_PATCH%
mkdir C:\TINYXML2
mkdir %TINYXML2_ROOT% && cd %TINYXML2_ROOT%
call git clone https://github.com/leethomason/tinyxml2.git
move tinyxml2 src && cd src
call git checkout %TINYXML2_MAJOR%.%TINYXML2_MINOR%.%TINYXML2_PATCH%
mkdir %TINYXML2_ROOT%\build && mkdir %TINYXML2_ROOT%\install && cd %TINYXML2_ROOT%\build
call %VS170COMNTOOLS%\VsDevCmd -host_arch=amd64 -arch=amd64 && cmake -DCMAKE_INSTALL_PREFIX=%TINYXML2_ROOT%\install -GNinja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON ../src  && ninja install

pathed /MACHINE /APPEND "%TINYXML2_ROOT%\install"
pathed /MACHINE /APPEND "%TINYXML2_ROOT%\install\bin"
setx /M TINYXML2_ROOT %TINYXML2_ROOT%\install
RMDIR /S /Q "%TINYXML2_ROOT%\src"
RMDIR /S /Q "%TINYXML2_ROOT%\build"
:tinyxml2_end

REM https://github.com/KarypisLab/METIS/archive/refs/tags/v5.1.1-DistDGL-v0.5.zip



REM Finalize environment
echo Finalizing environment...
call refreshenv && echo OK
setx /M PYTHONIOENCODING UTF-8
REM Strip duplicate PATH vars
pathed /MACHINE /SLIM

echo Done
