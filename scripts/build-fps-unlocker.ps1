$ErrorActionPreference = "Stop"

$PackageRoot = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $PackageRoot "FpsUnlocker\Native\UnlockerStub\UnlockerStub.vcxproj"
$Output = Join-Path $PackageRoot "FpsUnlocker\Native\UnlockerStub\bin\x64\Release\UnlockerStub.dll"

if (-not (Test-Path -LiteralPath $Project)) {
    throw "FPS unlocker project was not found: $Project"
}

$MsBuild = $null
$MsBuildCommand = Get-Command msbuild.exe -ErrorAction SilentlyContinue
if ($MsBuildCommand) {
    $MsBuild = $MsBuildCommand.Source
}

if (-not $MsBuild) {
    $VsWhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $VsWhere) {
        $MsBuild = & $VsWhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -find "MSBuild\**\Bin\MSBuild.exe" |
            Select-Object -First 1
    }
}

if (-not $MsBuild -or -not (Test-Path -LiteralPath $MsBuild)) {
    throw "MSBuild with the Visual Studio 2022 C++ x64 tools was not found. Install the Desktop development with C++ workload."
}

Write-Host "Building native FPS component..." -ForegroundColor Cyan
& $MsBuild $Project /m /t:Build /p:Configuration=Release /p:Platform=x64 /v:minimal
if ($LASTEXITCODE -ne 0) {
    throw "The native FPS component build failed with exit code $LASTEXITCODE."
}

if (-not (Test-Path -LiteralPath $Output)) {
    throw "The native build finished without creating UnlockerStub.dll: $Output"
}

Write-Host "Native FPS component built successfully:" -ForegroundColor Green
Write-Host $Output
