param(
    [string]$DistPath = ".\dist\SNI-Spoofing",
    [string]$OutputDir = ".\release\windows",
    [string]$AppVersion = "1.2.1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "build.ps1")
& (Join-Path $PSScriptRoot "installer.ps1") -DistPath $DistPath -OutputDir $OutputDir -AppVersion $AppVersion

$setupPath = Join-Path $OutputDir "SNI-Spoofing-Setup-v$AppVersion.exe"
if (-not (Test-Path $setupPath)) {
    throw "Installer was not created: $setupPath"
}

Write-Host "Release installer ready: $setupPath"
