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

if [ ! -d "SniSpoofingMac.xcodeproj" ]; then
  ./generate_xcode_project.sh
fi

BUILD_ARCH="$(normalize_arch "${BUILD_ARCH:-$(uname -m)}")"
if [ "${BUILD_ARCH}" = "unsupported" ]; then
  echo "Unsupported architecture: ${BUILD_ARCH:-$(uname -m)}" >&2
  echo "Set BUILD_ARCH to arm64 or x86_64." >&2
  exit 1
fi

BUILD_ROOT="$PWD/build/${BUILD_ARCH}"
HELPER_PATH="${BUILD_ROOT}/Debug/sni-proxy-helper"
CONFIG_PATH="${1:-$(cd .. && pwd)/config.json}"

shift $(( $# > 0 ? 1 : 0 )) || true

xcodebuild \
  -project SniSpoofingMac.xcodeproj \
  -target SniProxyHelper \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  ARCHS="${BUILD_ARCH}" \
  ONLY_ACTIVE_ARCH=YES \
  SYMROOT="${BUILD_ROOT}" \
  build >/dev/null

if [ ! -x "${HELPER_PATH}" ]; then
  echo "helper path resolve نشد."
  echo "build root: ${BUILD_ROOT}"
  echo "expected helper: ${HELPER_PATH}"
  exit 1
fi

echo "helper path: ${HELPER_PATH}"
echo "config path: ${CONFIG_PATH}"
echo "build arch: ${BUILD_ARCH}"
echo "dar hal ejra ba sudo..."

helper_pid=""

cleanup() {
  if [ -n "${helper_pid}" ] && kill -0 "${helper_pid}" 2>/dev/null; then
    echo
    echo "stopping helper pid=${helper_pid} ..."
    sudo kill -TERM "${helper_pid}" 2>/dev/null || true

    for _ in 1 2 3 4 5; do
      kill -0 "${helper_pid}" 2>/dev/null || break
      sleep 0.2
    done

    sudo kill -KILL "${helper_pid}" 2>/dev/null || true
  fi
}

trap cleanup EXIT HUP INT TERM

sudo -v
sudo "${HELPER_PATH}" --config "${CONFIG_PATH}" "$@" &
helper_pid=$!
wait "${helper_pid}"
