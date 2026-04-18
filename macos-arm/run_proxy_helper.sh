#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -d "SniSpoofingMac.xcodeproj" ]; then
  ./generate_xcode_project.sh
fi

BUILD_ROOT="$PWD/build"
HELPER_PATH="${BUILD_ROOT}/Debug/sni-proxy-helper"
CONFIG_PATH="${1:-$(cd .. && pwd)/config.json}"

shift $(( $# > 0 ? 1 : 0 )) || true

xcodebuild \
  -project SniSpoofingMac.xcodeproj \
  -target SniProxyHelper \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
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
