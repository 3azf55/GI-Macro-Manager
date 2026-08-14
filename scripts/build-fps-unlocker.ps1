param(
    [string]$PortableMsvcRoot = $env:MSVC_PORTABLE_ROOT
)

$ErrorActionPreference = "Stop"

$PackageRoot = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $PackageRoot "FpsUnlocker\Native\UnlockerStub\UnlockerStub.vcxproj"
$Source = Join-Path $PackageRoot "FpsUnlocker\Native\UnlockerStub\dllmain.cpp"
$BuildDirectory = Join-Path $PackageRoot "FpsUnlocker\Native\UnlockerStub\bin\x64\Release"
$ObjectDirectory = Join-Path $PackageRoot "FpsUnlocker\Native\UnlockerStub\obj\x64\Release"
$Output = Join-Path $PackageRoot "FpsUnlocker\Native\UnlockerStub\bin\x64\Release\UnlockerStub.dll"
$Object = Join-Path $ObjectDirectory "dllmain.obj"

if (-not (Test-Path -LiteralPath $Project)) {
    throw "FPS unlocker project was not found: $Project"
}

if (-not (Test-Path -LiteralPath $Source)) {
    throw "FPS unlocker source was not found: $Source"
}

function Import-BatchEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BatchFile
    )

    if (-not (Test-Path -LiteralPath $BatchFile -PathType Leaf)) {
        throw "MSVC environment script was not found: $BatchFile"
    }

    $CmdExe = Join-Path $env:SystemRoot "System32\cmd.exe"
    if (-not (Test-Path -LiteralPath $CmdExe -PathType Leaf)) {
        $CmdCommand = Get-Command cmd.exe -ErrorAction SilentlyContinue
        if (-not $CmdCommand) {
            throw "cmd.exe was not found; the portable MSVC environment cannot be loaded."
        }

        $CmdExe = $CmdCommand.Source
    }

    $EscapedBatchFile = $BatchFile.Replace('"', '""')
    $Command = 'call "{0}" >nul && set' -f $EscapedBatchFile
    $EnvironmentLines = & $CmdExe /d /c $Command
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -ne 0) {
        throw "MSVC environment setup failed with exit code $ExitCode."
    }

    foreach ($Line in $EnvironmentLines) {
        if ($Line -match '^([^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
        }
    }
}

function Find-PortableSetupScript {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "MSVC_PORTABLE_ROOT does not exist or is not a directory: $Root"
    }

    $Candidates = @(
        (Join-Path $Root "setup_x64.bat"),
        (Join-Path $Root "vcvars64.bat"),
        (Join-Path $Root "Auxiliary\Build\vcvars64.bat"),
        (Join-Path $Root "VC\Auxiliary\Build\vcvars64.bat")
    )

    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            return $Candidate
        }
    }

    throw "No x64 MSVC setup script was found under '$Root'. Expected setup_x64.bat or vcvars64.bat."
}

$UsePortableCompiler = -not [string]::IsNullOrWhiteSpace($PortableMsvcRoot)
if ($UsePortableCompiler) {
    $PortableSetup = Find-PortableSetupScript -Root $PortableMsvcRoot
    Write-Host "Loading portable MSVC environment: $PortableSetup" -ForegroundColor Cyan
    Import-BatchEnvironment -BatchFile $PortableSetup
}

$MsBuild = $null
if (-not $UsePortableCompiler) {
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
}

$ClCommand = Get-Command cl.exe -ErrorAction SilentlyContinue

if ($UsePortableCompiler -and -not $ClCommand) {
    throw "The portable MSVC environment loaded, but cl.exe was not found. Check MSVC_PORTABLE_ROOT and the Windows SDK included by setup_x64.bat."
}

if ($MsBuild -and (Test-Path -LiteralPath $MsBuild)) {
    Write-Host "Building native FPS component with MSBuild..." -ForegroundColor Cyan
    & $MsBuild $Project /m /t:Build /p:Configuration=Release /p:Platform=x64 /v:minimal
    if ($LASTEXITCODE -ne 0) {
        throw "The native FPS component MSBuild build failed with exit code $LASTEXITCODE."
    }
}
elseif ($ClCommand) {
    New-Item -ItemType Directory -Force -Path $BuildDirectory, $ObjectDirectory | Out-Null
    Remove-Item -LiteralPath $Output -Force -ErrorAction SilentlyContinue

    $CompilerArguments = @(
        "/nologo"
        "/LD"
        "/std:c++20"
        "/O2"
        "/GL"
        "/W4"
        "/WX"
        "/permissive-"
        "/EHsc"
        "/MT"
        "/Gy"
        "/Oi"
        "/DWIN32_LEAN_AND_MEAN"
        "/DNOMINMAX"
        "/DNDEBUG"
        "/Fo$Object"
        $Source
        "/link"
        "/NOLOGO"
        "/OUT:$Output"
        "/MACHINE:X64"
        "/LTCG"
        "/OPT:REF"
        "/OPT:ICF"
        "/INCREMENTAL:NO"
        "/MANIFEST:NO"
        "kernel32.lib"
        "user32.lib"
        "ntdll.lib"
    )

    $CompilerLabel = if ($UsePortableCompiler) { "portable MSVC" } else { "cl.exe" }
    Write-Host "Building native FPS component with $CompilerLabel..." -ForegroundColor Cyan
    & $ClCommand.Source @CompilerArguments
    if ($LASTEXITCODE -ne 0) {
        throw "The native FPS component $CompilerLabel build failed with exit code $LASTEXITCODE."
    }
}
else {
    throw @"
Neither MSBuild with the Visual C++ tools nor cl.exe was found.
Install the Visual Studio Desktop development with C++ workload, or set
MSVC_PORTABLE_ROOT to the folder containing setup_x64.bat before running this script.
"@
}

if (-not (Test-Path -LiteralPath $Output)) {
    throw "The native build finished without creating UnlockerStub.dll: $Output"
}

Write-Host "Native FPS component built successfully:" -ForegroundColor Green
Write-Host $Output
