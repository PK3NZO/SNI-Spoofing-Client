## Highlights

- Fixed the macOS launch-time entitlement and provisioning mismatch that could prevent the installed app from opening
- Added embedded provisioning profile handling for both the host app and the packet tunnel extension in the release-signing flow
- Upgraded the macOS DMG installer window to a styled drag-and-drop layout for both `arm64` and `x86_64`
- Completed signed, notarized, and stapled macOS release artifacts for Apple Silicon and Intel Macs

## Assets

- `SniSpoofingClient-macos-arm64-v1.2.2.dmg`
- `SniSpoofingClient-macos-x86_64-v1.2.2.dmg`
- `checksums-v1.2.2.txt`

## Notes

- Download the DMG matching your Mac architecture
- The macOS app bundle and DMG are both signed, notarized, and stapled
- If you report a bug, include architecture, mode (`Proxy` or `Tunnel`), and whether the issue happened before or after installation
