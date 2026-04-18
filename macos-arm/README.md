# macOS Build Workspace

In پوشه source, scripts, va release tooling e macOS gharar darad.

## Supported architectures

- `arm64`
- `x86_64`

## Version

- `1.2.1`
- minimum macOS: `13.3`

## Quick start

```bash
cd macos-arm
./generate_xcode_project.sh
./build_arm_debug.sh
./build_x86_64_debug.sh
```

## Release scripts

```bash
cd macos-arm
./build_arm_release.sh
./build_x86_64_release.sh
./sign_release.sh arm64
./sign_release.sh x86_64
./package_dmg.sh arm64
./package_dmg.sh x86_64
./notarize_dmg.sh arm64
./notarize_dmg.sh x86_64
```

## Generic scripts

```bash
cd macos-arm
./build_debug.sh arm64
./build_debug.sh x86_64
./build_release.sh arm64
./build_release.sh x86_64
./package_release.sh arm64
./package_release.sh x86_64
./package_dmg.sh arm64
./package_dmg.sh x86_64
./generate_checksums.sh
./release_macos.sh arm64
./release_macos.sh x86_64
```

## Local helper run

```bash
cd macos-arm
./run_proxy_helper.sh ../config.json
```

## Notes

- signed/notarized public releases should use the DMG flow
- helper and Xray are bundled per architecture
- the public macOS release guide lives here:
  - [../docs/macos-release-guide.md](../docs/macos-release-guide.md)
