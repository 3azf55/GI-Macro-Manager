@echo off
setlocal
title Macro Manager NuGet Diagnostic

cd /d "%~dp0.."

echo === .NET SDK ===
dotnet --version
echo.

echo === Configured NuGet sources ===
dotnet nuget list source
echo.

echo === Testing nuget.org ===
powershell -NoProfile -Command ^
  "try { $r = Invoke-WebRequest 'https://api.nuget.org/v3/index.json' -UseBasicParsing -TimeoutSec 20; Write-Host ('HTTP ' + [int]$r.StatusCode) -ForegroundColor Green; exit 0 } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"

echo.
echo === Restore using this package's NuGet.Config ===
dotnet restore "UIHost\UMM.UI.csproj" --configfile "NuGet.Config"

echo.
pause
