@echo off
rem Plenara — build the Windows release binary. Wraps .tools\flutter.
rem Usage:  build
setlocal
set ROOT=%~dp0
echo [plenara] building Windows release...
pushd "%ROOT%app"
call "%ROOT%.tools\flutter\bin\flutter.bat" build windows --release
set ERR=%ERRORLEVEL%
popd
if "%ERR%"=="0" ( echo [plenara] built app\build\windows\x64\runner\Release\plenara_app.exe ) else ( echo [plenara] build FAILED ^(exit %ERR%^) )
exit /b %ERR%
