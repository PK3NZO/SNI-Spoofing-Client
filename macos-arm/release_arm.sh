#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
exec ./release_macos.sh arm64 "$@"
