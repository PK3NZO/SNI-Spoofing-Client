param(
    [string]$Destination = ".\resources\windows\xray.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$destinationPath = [System.IO.Path]::GetFullPath($Destination)
$destinationDir = Split-Path -Parent $destinationPath
New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/XTLS/Xray-core/releases/latest"
$asset = $release.assets | Where-Object { $_.name -eq "Xray-windows-64.zip" } | Select-Object -First 1
if (-not $asset) {
    throw "Asset `Xray-windows-64.zip` was not found in the latest release."
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sni-xray-" + [System.Guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $tempRoot "xray.zip"
$extractDir = Join-Path $tempRoot "extract"
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

try {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

    $downloadedBinary = Get-ChildItem -Path $extractDir -Recurse -Filter "xray.exe" | Select-Object -First 1
    if (-not $downloadedBinary) {
        throw "xray.exe was not found inside the downloaded archive."
    }

    Copy-Item -Force $downloadedBinary.FullName $destinationPath
    Write-Host "Downloaded xray.exe to $destinationPath"
}
finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Recurse -Force $tempRoot
    }
}
