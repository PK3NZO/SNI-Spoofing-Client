#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

VERSION="$(tr -d '\n' < "$PWD/VERSION")"
DIST_DIR="$PWD/dist"
CHECKSUMS_PATH="${DIST_DIR}/checksums-v${VERSION}.txt"

if [ ! -d "${DIST_DIR}" ]; then
  echo "dist directory not found at: ${DIST_DIR}" >&2
  echo "Build/package the release assets first." >&2
  exit 1
fi

assets=("${DIST_DIR}"/SniSpoofingClient-macos-*-v"${VERSION}".dmg(N))
if [ "${#assets[@]}" -eq 0 ]; then
  echo "No DMG assets found for version ${VERSION} in ${DIST_DIR}" >&2
  exit 1
fi

(
  cd "${DIST_DIR}"
  shasum -a 256 SniSpoofingClient-macos-*-v"${VERSION}".dmg > "${CHECKSUMS_PATH:t}"
)

echo
echo "Checksums ready:"
echo "  version: ${VERSION}"
echo "  file: ${CHECKSUMS_PATH}"
