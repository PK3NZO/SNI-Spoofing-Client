#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

VERSION="$(tr -d '\n' < "$PWD/VERSION")"
SIGNING_IDENTITY="${MACOS_SIGN_IDENTITY:-}"

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
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sni-dmg-${ARCH}-XXXXXX")"
STAGE_DIR="${TMP_DIR}/stage"
VOL_NAME="SNI-Spoofing Client ${VERSION} (${ARCH})"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

if [ ! -d "${APP_PATH}" ]; then
  echo "Release app not found at: ${APP_PATH}" >&2
  echo "Run ./build_release.sh ${ARCH} first, or ./sign_release.sh ${ARCH} if you want a signed DMG." >&2
  exit 1
fi

mkdir -p "${DIST_DIR}" "${STAGE_DIR}"
rm -f "${DMG_PATH}"

cp -R "${APP_PATH}" "${STAGE_DIR}/"
ln -s /Applications "${STAGE_DIR}/Applications"

hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${STAGE_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

if [ -n "${SIGNING_IDENTITY}" ]; then
  codesign --force --sign "${SIGNING_IDENTITY}" --timestamp --options runtime "${DMG_PATH}"
fi

echo
echo "DMG package ready:"
echo "  arch: ${ARCH}"
echo "  version: ${VERSION}"
echo "  dmg: ${DMG_PATH}"
