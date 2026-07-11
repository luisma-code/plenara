@echo off
rem Plenara — build the Windows release binary. Wraps .tools\flutter.
rem Usage:  build
setlocal
set ROOT=%~dp0
rem flutter_tts's Windows plugin restores its WinRT deps via NuGet — fetch nuget.exe once if absent.
if not exist "%ROOT%.tools\nuget.exe" (
  echo [plenara] fetching nuget.exe ^(needed by the flutter_tts Windows plugin^)...
  powershell -NoProfile -Command "Invoke-WebRequest -Uri https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -OutFile '%ROOT%.tools\nuget.exe'"
)
set PATH=%ROOT%.tools;%PATH%
echo [plenara] building Windows release...
pushd "%ROOT%app"
call "%ROOT%.tools\flutter\bin\flutter.bat" build windows --release
set ERR=%ERRORLEVEL%
popd
if "%ERR%"=="0" ( echo [plenara] built app\build\windows\x64\runner\Release\plenara_app.exe ) else ( echo [plenara] build FAILED ^(exit %ERR%^) )
exit /b %ERR%
