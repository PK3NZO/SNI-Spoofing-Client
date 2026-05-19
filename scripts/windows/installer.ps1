param(
    [string]$DistPath = ".\dist\SNI-Spoofing",
    [string]$OutputDir = ".\release\windows",
    [string]$AppVersion = "1.2.1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $DistPath)) {
    throw "Dist path not found: $DistPath . Run .\\scripts\\windows\\build.ps1 first."
}

$exePath = Join-Path $DistPath "SNI-Spoofing.exe"
if (-not (Test-Path $exePath)) {
    throw "Executable not found: $exePath"
}

$xrayBundledPath = Join-Path $DistPath "resources\windows\xray.exe"
if (-not (Test-Path $xrayBundledPath)) {
    Write-Warning "Bundled xray.exe was not found. The installer will be created, but proxy-link runtime will be incomplete without xray."
}

$compilerPath = $env:INNO_SETUP_COMPILER
if (-not $compilerPath) {
    $candidates = @(
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            $compilerPath = $candidate
            break
        }
    }
}

if (-not $compilerPath) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host "ISCC.exe was not found. Installing Inno Setup 6 with winget..."
        & $winget.Source install --exact --id JRSoftware.InnoSetup --accept-source-agreements --accept-package-agreements
        $candidates = @(
            "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
            "C:\Program Files\Inno Setup 6\ISCC.exe"
        )
        foreach ($candidate in $candidates) {
            if (Test-Path $candidate) {
                $compilerPath = $candidate
                break
            }
        }
    }
}

if (-not $compilerPath) {
    throw "ISCC.exe was not found and automatic installation did not succeed."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$issPath = Join-Path $PSScriptRoot "installer.iss"

& $compilerPath `
  "/DMyAppVersion=$AppVersion" `
  "/DDistPath=$((Resolve-Path $DistPath).Path)" `
  "/DOutputDir=$((Resolve-Path $OutputDir).Path)" `
  $issPath

Write-Host "Windows installer ready in $OutputDir"
