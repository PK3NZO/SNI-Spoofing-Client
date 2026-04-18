#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
rm -rf SniSpoofingMac.xcodeproj
xcodegen generate

python3 - <<'PY'
from pathlib import Path
import time

pbxproj = Path.cwd() / "SniSpoofingMac.xcodeproj" / "project.pbxproj"
for _ in range(50):
    if pbxproj.exists():
        break
    time.sleep(0.1)
text = pbxproj.read_text()
sanitized_lines = []
for line in text.splitlines():
    stripped = line.strip()
    if stripped.startswith("DEVELOPMENT_TEAM = "):
        continue
    if stripped.startswith("DevelopmentTeam = "):
        continue
    sanitized_lines.append(line)
pbxproj.write_text("\n".join(sanitized_lines) + "\n")
PY
