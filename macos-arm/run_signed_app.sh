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

BUILD_ARCH="$(normalize_arch "${1:-$(uname -m)}")"
if [ "${BUILD_ARCH}" = "unsupported" ]; then
  echo "Unsupported architecture: ${1:-$(uname -m)}" >&2
  echo "Use one of: arm64, x86_64" >&2
  exit 1
fi

APP_PATH="$PWD/build/${BUILD_ARCH}/Debug/SniSpoofingMac.app"

if [ ! -d "$APP_PATH" ]; then
  echo "Signed app bundle not found at: $APP_PATH" >&2
  echo "Run ./build_debug.sh ${BUILD_ARCH} first." >&2
  exit 1
fi

if codesign -dv "$APP_PATH" 2>&1 | grep -q "Signature=adhoc"; then
  echo "Refusing to install ad-hoc signed app: $APP_PATH" >&2
  echo "Run ./build_debug.sh ${BUILD_ARCH} with provisioning enabled and check signing output." >&2
  exit 1
fi

rm -rf /Applications/SniSpoofingMac.app
rsync -a --delete "$APP_PATH/" /Applications/SniSpoofingMac.app/
open /Applications/SniSpoofingMac.app
