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

./sign_release.sh "${ARCH}"

if [ -n "${NOTARYTOOL_PROFILE:-}" ]; then
  ./notarize_app.sh "${ARCH}"
fi

./package_dmg.sh "${ARCH}"

if [ -n "${NOTARYTOOL_PROFILE:-}" ]; then
  ./notarize_dmg.sh "${ARCH}"
else
  echo
  echo "NOTARYTOOL_PROFILE set نشده. DMG sakhte shod vali notarize nashod."
fi

./generate_checksums.sh
