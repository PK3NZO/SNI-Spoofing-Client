#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

VERSION="$(tr -d '\n' < "$PWD/VERSION")"
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-}"

normalize_arch() {
  local raw_arch="${1:-}"
  case "${raw_arch}" in
    arm64|aarch64)
      echo "arm64"
      ;;
    x86_64|amd64)
      echo "x86_64"
      ;;
    *)
      echo "unsupported"
      ;;
  esac
}

ARCH="$(normalize_arch "${1:-$(uname -m)}")"
if [ "${ARCH}" = "unsupported" ]; then
  echo "Unsupported architecture: ${1:-$(uname -m)}" >&2
  echo "Use one of: arm64, x86_64" >&2
  exit 1
fi

if [ -z "${NOTARY_PROFILE}" ]; then
  echo "NOTARYTOOL_PROFILE is required." >&2
  echo "Example: export NOTARYTOOL_PROFILE='SniSpoofingNotary'" >&2
  exit 1
fi

DMG_PATH="$PWD/dist/SniSpoofingClient-macos-${ARCH}-v${VERSION}.dmg"
if [ ! -f "${DMG_PATH}" ]; then
  echo "DMG not found at: ${DMG_PATH}" >&2
  echo "Run ./package_dmg.sh ${ARCH} first." >&2
  exit 1
fi

xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${DMG_PATH}"

echo
echo "Notarized DMG ready:"
echo "  arch: ${ARCH}"
echo "  version: ${VERSION}"
echo "  dmg: ${DMG_PATH}"
