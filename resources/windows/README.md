Place `xray.exe` here for Windows local builds and packaged releases.

Supported discovery order:

1. `XRAY_EXECUTABLE` environment variable
2. `resources/windows/xray.exe`
3. bundled `resources/windows/xray.exe` inside the packaged app
4. `xray.exe` in `PATH`
