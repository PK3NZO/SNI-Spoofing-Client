## Highlights

- Native macOS release track for both `arm64` and `x86_64`
- Separate DMG assets for Apple Silicon and Intel Macs
- Cleaner release packaging flow with dedicated build, sign, DMG, notarize, and checksum scripts
- Improved public-repo hygiene checks to reduce the risk of leaking private local paths or signing metadata
- Refreshed GitHub-facing project docs, issue templates, contribution guide, and security policy

## Assets

- `SniSpoofingClient-macos-arm64-v1.2.1.dmg`
- `SniSpoofingClient-macos-x86_64-v1.2.1.dmg`
- `checksums-v1.2.1.txt`

## Notes

- Download the DMG matching your Mac architecture
- `Proxy` and `Tunnel` modes should both be validated before broad rollout
- If you hit a packaging or connection bug, include architecture and mode in the issue report
