#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
exec ./build_release.sh arm64 "$@"
