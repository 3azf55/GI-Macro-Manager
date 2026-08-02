@echo off
setlocal
title Macro Manager Builder

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-and-stage.ps1"
if errorlevel 1 (
  echo.
  echo ============================================================
  echo BUILD FAILED. The dist folder is not a valid completed build.
  echo Read the error shown above and do not run the incomplete files.
  echo ============================================================
  echo.
  pause
  exit /b 1
)

echo.
echo Build succeeded.
pause
exit /b 0
