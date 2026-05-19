# Windows workflow

Run the app:

```powershell
.\scripts\windows\run.ps1
```

Use a custom config:

```powershell
.\scripts\windows\run.ps1 -ConfigPath .\config.json
```

Build a distributable:

```powershell
.\scripts\windows\build.ps1
```

Create a zip package from the built app:

```powershell
.\scripts\windows\package.ps1
```

Create a Windows installer (`Setup.exe`) from the built app:

```powershell
.\scripts\windows\installer.ps1
```

Build the final end-user installer in one shot:

```powershell
.\scripts\windows\release.ps1
```

What happens automatically:

- if `xray.exe` is missing, the build script downloads the latest official Windows x64 Xray release
- if `Inno Setup 6` is missing, the installer script tries to install it with `winget`
- the final installer is written to:
  - `release/windows/SNI-Spoofing-Setup-v1.2.1.exe`

GitHub Actions:

- the repo now includes `.github/workflows/windows-installer.yml`
- you can run it from the GitHub Actions tab and download the built installer artifact
