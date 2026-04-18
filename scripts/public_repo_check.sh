#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

echo "Running public repo hygiene checks..."

patterns=(
  "DEVELOPMENT_TEAM = "
  "DevelopmentTeam = "
  "NMVD5BGX82"
  "/Users/"
  "PRIVATE KEY"
  "BEGIN CERTIFICATE"
  "BEGIN RSA PRIVATE KEY"
  "BEGIN OPENSSH PRIVATE KEY"
)

failed=0

for pattern in "${patterns[@]}"; do
  if rg -n --hidden \
    --glob '!.git' \
    --glob '!scripts/public_repo_check.sh' \
    --glob '!macos-arm/generate_xcode_project.sh' \
    --glob '!macos-arm/build/**' \
    --glob '!macos-arm/dist/**' \
    --glob '!build/**' \
    --glob '!dist/**' \
    --glob '!*.xcworkspace/**' \
    --glob '!*.xcuserstate' \
    --glob '!*.xcuserdata/**' \
    --glob '!*.log' \
    --glob '!*.tmp' \
    --fixed-strings "${pattern}" . >/dev/null 2>&1; then
    echo "Found blocked pattern: ${pattern}"
    rg -n --hidden \
      --glob '!.git' \
      --glob '!scripts/public_repo_check.sh' \
      --glob '!macos-arm/generate_xcode_project.sh' \
      --glob '!macos-arm/build/**' \
      --glob '!macos-arm/dist/**' \
      --glob '!build/**' \
      --glob '!dist/**' \
      --glob '!*.xcworkspace/**' \
      --glob '!*.xcuserstate' \
      --glob '!*.xcuserdata/**' \
      --glob '!*.log' \
      --glob '!*.tmp' \
      --fixed-strings "${pattern}" . || true
    failed=1
  fi
done

if find . \( -name '*.p12' -o -name '*.cer' -o -name '*.mobileprovision' -o -name '*.dmg' -o -name '*.pkg' \) \
  ! -path './.git/*' \
  ! -path './macos-arm/build/*' \
  ! -path './macos-arm/dist/*' | grep -q .; then
  echo "Found blocked binary/certificate-style artifacts:"
  find . \( -name '*.p12' -o -name '*.cer' -o -name '*.mobileprovision' -o -name '*.dmg' -o -name '*.pkg' \) \
    ! -path './.git/*' \
    ! -path './macos-arm/build/*' \
    ! -path './macos-arm/dist/*'
  failed=1
fi

if [ "${failed}" -ne 0 ]; then
  echo "Public repo check failed."
  exit 1
fi

echo "Public repo check passed."
