@echo off
rem Plenara — dogfood CLI. Drives the real engine against your data folder.
rem Usage:  dogfood "add milk to my list"      (one-shot)
rem         dogfood -v                          (interactive, verbose)
rem         echo "..." | dogfood                (piped)
setlocal
set ROOT=%~dp0
pushd "%ROOT%v0"
"%ROOT%.tools\dart-sdk\bin\dart.exe" run bin/dogfood.dart %*
set ERR=%ERRORLEVEL%
popd
exit /b %ERR%
