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

if [ -z "${SIGNING_IDENTITY}" ]; then
  echo "MACOS_SIGN_IDENTITY is required." >&2
  echo "Example: export MACOS_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'" >&2
  exit 1
fi

./build_release.sh "${ARCH}"

APP_PATH="$PWD/build/${ARCH}/Release/SniSpoofingMac.app"
HELPER_PATH="${APP_PATH}/Contents/Resources/sni-proxy-helper"
XRAY_ARM64_PATH="${APP_PATH}/Contents/Resources/xray-arm64.bin"
XRAY_X86_PATH="${APP_PATH}/Contents/Resources/xray-x86_64.bin"
APPEX_PATH="${APP_PATH}/Contents/PlugIns/PacketTunnel.appex"

if [ ! -d "${APP_PATH}" ]; then
  echo "Release app not found at: ${APP_PATH}" >&2
  exit 1
fi

for required_path in "${HELPER_PATH}" "${XRAY_ARM64_PATH}" "${XRAY_X86_PATH}" "${APPEX_PATH}"; do
  if [ ! -e "${required_path}" ]; then
    echo "Required bundled path missing: ${required_path}" >&2
    exit 1
  fi
done

codesign --force --sign "${SIGNING_IDENTITY}" --timestamp --options runtime "${XRAY_ARM64_PATH}"
codesign --force --sign "${SIGNING_IDENTITY}" --timestamp --options runtime "${XRAY_X86_PATH}"
codesign --force --sign "${SIGNING_IDENTITY}" --timestamp --options runtime "${HELPER_PATH}"
codesign --force --sign "${SIGNING_IDENTITY}" --timestamp --options runtime \
  --entitlements "$PWD/PacketTunnel/SniPacketTunnel.entitlements" \
  "${APPEX_PATH}"
codesign --force --sign "${SIGNING_IDENTITY}" --timestamp --options runtime \
  --entitlements "$PWD/App/SniSpoofingMac.entitlements" \
  "${APP_PATH}"

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

echo
echo "Signed release ready:"
echo "  arch: ${ARCH}"
echo "  version: ${VERSION}"
echo "  app: ${APP_PATH}"
