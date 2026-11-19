@echo off
setlocal
cd /d "%~dp0"
set "PYTHONNOUSERSITE=1"
set "PYTHONUTF8=1"
if "%~1"=="" (
  "%~dp0python\python.exe" -m __MODULE__
  pause
) else (
  "%~dp0python\python.exe" %*
)
exit /b %ERRORLEVEL%
