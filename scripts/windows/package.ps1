param(
    [string]$DistPath = ".\dist\SNI-Spoofing",
    [string]$OutputDir = ".\release\windows"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $DistPath)) {
    throw "Dist path not found: $DistPath . Aval .\scripts\windows\build.ps1 ra ejra kon."
}

$exePath = Join-Path $DistPath "SNI-Spoofing.exe"
if (-not (Test-Path $exePath)) {
    throw "Executable not found: $exePath"
}

$xrayBundledPath = Join-Path $DistPath "resources\windows\xray.exe"
if (-not (Test-Path $xrayBundledPath)) {
    Write-Warning "Bundled xray.exe peyda نشد. Package ساخته می‌شود ama proxy-link runtime bedune xray کامل nist."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$archivePath = Join-Path $OutputDir "SNI-Spoofing-windows.zip"
if (Test-Path $archivePath) {
    Remove-Item -Force $archivePath
}

Compress-Archive -Path (Join-Path $DistPath "*") -DestinationPath $archivePath -Force
Write-Host "Windows package ready: $archivePath"
