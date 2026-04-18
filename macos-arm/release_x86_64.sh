#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
exec ./release_macos.sh x86_64 "$@"
