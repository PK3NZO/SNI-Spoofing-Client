Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path "resources/windows" | Out-Null

$xraySource = $env:XRAY_EXECUTABLE
if (-not $xraySource) {
    $candidate = Get-Command xray.exe -ErrorAction SilentlyContinue
    if ($candidate) {
        $xraySource = $candidate.Source
    }
}

if ($xraySource) {
    Copy-Item -Force $xraySource "resources/windows/xray.exe"
    Write-Host "Bundled xray.exe from $xraySource"
} else {
    Write-Host "xray.exe was not found. Downloading the latest Windows build..."
    & (Join-Path $PSScriptRoot "fetch-xray.ps1") -Destination "resources/windows/xray.exe"
}

python -m pip install -r requirements.txt
python -m pip install pyinstaller
pyinstaller `
  --noconfirm `
  --clean `
  --windowed `
  --name "SNI-Spoofing" `
  --collect-submodules PySide6 `
  --hidden-import pydivert `
  --add-data "resources/windows;resources/windows" `
  main.py
