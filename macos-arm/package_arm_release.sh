#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
exec ./package_release.sh arm64 "$@"
