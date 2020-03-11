@ECHO OFF 

set arg1=%1

:loop
tasklist.exe | findstr %arg1% > nul
if "%ERRORLEVEL%"=="0" exit /b 0
echo %arg1% is not running ... 
ping -n 10 127.0.0.1 > nul
goto loop
