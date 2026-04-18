# macOS Release Guide

This document covers the release flow for `SNI-Spoofing Client` on macOS.

## 1. Architectures

Two separate release tracks are supported:

- `arm64`
- `x86_64`

Recommended release assets:

- `SniSpoofingClient-macos-arm64-v1.2.1.dmg`
- `SniSpoofingClient-macos-x86_64-v1.2.1.dmg`
- `checksums-v1.2.1.txt`

## 2. Build

Unsigned local verification:

```bash
cd macos-arm
ALLOW_UNSIGNED_APP_BUILD=1 ./build_arm_release.sh
ALLOW_UNSIGNED_APP_BUILD=1 ./build_x86_64_release.sh
```

## 3. Sign

Export your Developer ID Application identity:

```bash
export MACOS_SIGN_IDENTITY="Developer ID Application: YOUR NAME OR ORG (TEAMID)"
```

Then sign each release:

```bash
cd macos-arm
./sign_release.sh arm64
./sign_release.sh x86_64
```

What gets signed:

- bundled `xray-arm64.bin`
- bundled `xray-x86_64.bin`
- bundled `sni-proxy-helper`
- `PacketTunnel.appex`
- `SniSpoofingMac.app`

## 4. Create DMG

```bash
cd macos-arm
./package_dmg.sh arm64
./package_dmg.sh x86_64
```

If `MACOS_SIGN_IDENTITY` is set, the DMG itself is also signed.

## 5. Notarize

Store credentials once:

```bash
xcrun notarytool store-credentials "SniSpoofingNotary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

Then:

```bash
export NOTARYTOOL_PROFILE="SniSpoofingNotary"

cd macos-arm
./notarize_dmg.sh arm64
./notarize_dmg.sh x86_64
```

Or run the whole flow:

```bash
export MACOS_SIGN_IDENTITY="Developer ID Application: YOUR NAME OR ORG (TEAMID)"
export NOTARYTOOL_PROFILE="SniSpoofingNotary"

cd macos-arm
./release_arm.sh
./release_x86_64.sh
./generate_checksums.sh
```

## 6. DMG vs PKG

### DMG

- best for drag-and-drop app distribution
- familiar for most Mac users
- user opens the DMG and drags the app into `Applications`
- simpler for first public release

### PKG

- installer-style flow
- can feel more “enterprise”
- useful when you must install files into fixed locations with a guided setup
- can be one-click, but it is more intrusive than a drag-and-drop DMG

Recommended for this project right now:

- start with `DMG`
- move to `PKG` later only if install-time system setup becomes too complex

## 7. Can users see who signed the app?

Yes.

For a public macOS app signed with Developer ID, the signing identity can be inspected. If you do not want your personal legal name visible, the correct solution is:

- sign with an organization/company identity
- not a personal Developer ID identity

This is not something you can safely hide inside a properly signed public macOS release.

## 8. Final pre-release checklist

- app launches on a clean machine
- `Proxy` mode tested
- `Tunnel` mode tested
- invalid config handling tested
- disconnect/cancel tested
- app close/quit behavior tested
- helper cleanup tested
- DMG opens correctly
- signed app verifies:
  - `codesign --verify --deep --strict`
- notarized DMG staples successfully
