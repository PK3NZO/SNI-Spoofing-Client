#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
exec ./build_debug.sh arm64 "$@"
