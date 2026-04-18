#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

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

./build_release.sh "${ARCH}"

APP_PATH="$PWD/build/${ARCH}/Release/SniSpoofingMac.app"
DIST_DIR="$PWD/dist"
ZIP_PATH="${DIST_DIR}/SniSpoofingMac-macos-${ARCH}.zip"

if [ ! -d "${APP_PATH}" ]; then
  echo "Release app not found at: ${APP_PATH}" >&2
  exit 1
fi

mkdir -p "${DIST_DIR}"
rm -f "${ZIP_PATH}"

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo
echo "Release package ready:"
echo "  arch: ${ARCH}"
echo "  zip: ${ZIP_PATH}"
