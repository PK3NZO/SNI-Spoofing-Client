#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
exec ./package_release.sh x86_64 "$@"
