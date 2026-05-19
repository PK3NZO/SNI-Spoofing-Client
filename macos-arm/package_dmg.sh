#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

VERSION="$(tr -d '\n' < "$PWD/VERSION")"
SIGNING_IDENTITY="${MACOS_SIGN_IDENTITY:-}"
APP_DISPLAY_NAME="SNI-Spoofing Client"

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

APP_PATH="$PWD/build/${ARCH}/Release/SniSpoofingMac.app"
DIST_DIR="$PWD/dist"
DMG_PATH="${DIST_DIR}/SniSpoofingClient-macos-${ARCH}-v${VERSION}.dmg"
VOL_NAME="SNI-Spoofing Client ${VERSION} (${ARCH})"

if [ ! -d "${APP_PATH}" ]; then
  echo "Release app not found at: ${APP_PATH}" >&2
  echo "Run ./build_release.sh ${ARCH} first, or ./sign_release.sh ${ARCH} if you want a signed DMG." >&2
  exit 1
fi

mkdir -p "${DIST_DIR}"
rm -f "${DMG_PATH}"

"$PWD/create_pretty_dmg.sh" \
  "${APP_PATH}" \
  "${DMG_PATH}" \
  "${VOL_NAME}" \
  "${APP_DISPLAY_NAME}" \
  "${SIGNING_IDENTITY}"

echo
echo "DMG package ready:"
echo "  arch: ${ARCH}"
echo "  version: ${VERSION}"
echo "  dmg: ${DMG_PATH}"
