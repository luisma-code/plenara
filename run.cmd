@echo off
rem Plenara — launch the app. Wraps the deep .tools\flutter toolchain so you don't have to.
rem Usage:  run           (from the repo root, in cmd or PowerShell as .\run.cmd)
setlocal
set ROOT=%~dp0
set EXE=%ROOT%app\build\windows\x64\runner\Release\plenara_app.exe
if not exist "%EXE%" (
  echo [plenara] No release build found - building once (this takes ~1 min)...
  call "%ROOT%build.cmd" || exit /b 1
)
echo [plenara] launching %EXE%
start "" "%EXE%"
