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

./generate_xcode_project.sh

BUILD_ROOT="$PWD/build/${ARCH}"
rm -rf "${BUILD_ROOT}"

main_build_args=(
  -project SniSpoofingMac.xcodeproj
  -scheme SniSpoofingMac
  -configuration Debug
  -destination "platform=macOS,arch=${ARCH}"
  -allowProvisioningUpdates
  -allowProvisioningDeviceRegistration
  ARCHS="${ARCH}"
  ONLY_ACTIVE_ARCH=YES
  SYMROOT="${BUILD_ROOT}"
)

if [ "${ALLOW_UNSIGNED_APP_BUILD:-0}" = "1" ]; then
  echo "Unsigned app build requested. Tunnel mode run nemishe va signed app lazeme."
  main_build_args+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="")
fi

xcodebuild "${main_build_args[@]}" build

xcodebuild \
  -project SniSpoofingMac.xcodeproj \
  -target SniProxyHelper \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  ARCHS="${ARCH}" \
  ONLY_ACTIVE_ARCH=YES \
  SYMROOT="${BUILD_ROOT}" \
  build

echo
echo "Debug build ready:"
echo "  arch: ${ARCH}"
echo "  app: ${BUILD_ROOT}/Debug/SniSpoofingMac.app"
echo "  helper: ${BUILD_ROOT}/Debug/sni-proxy-helper"
