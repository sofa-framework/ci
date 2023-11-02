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

echo Done
