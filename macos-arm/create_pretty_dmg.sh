#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE="${1:?app bundle is required}"
DMG_PATH="${2:?output dmg path is required}"
VOLUME_NAME="${3:?volume name is required}"
APP_DISPLAY_NAME="${4:?app display name is required}"
SIGN_IDENTITY="${5:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "Missing required tool: create-dmg" >&2
  echo "Install it with: brew install create-dmg" >&2
  exit 1
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

APP_NAME="$(basename "$APP_BUNDLE" .app)"
DMG_DIR="$(dirname "$DMG_PATH")"
WORK_DIR="$DMG_DIR/dmg_source"
ASSET_DIR="$DMG_DIR/dmg_assets"
BACKGROUND_PATH="$ASSET_DIR/background.png"
APPLICATIONS_ICON_SOURCE="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns"
APPLICATIONS_ICON_PNG="$ASSET_DIR/applications-folder.png"
APPLICATIONS_ICON_RSRC="$ASSET_DIR/applications-folder.rsrc"

rm -rf "$WORK_DIR" "$ASSET_DIR" "$DMG_PATH"
mkdir -p "$WORK_DIR" "$ASSET_DIR"

swift "$SCRIPT_DIR/create_dmg_background.swift" "$BACKGROUND_PATH" "$APP_DISPLAY_NAME"

ditto "$APP_BUNDLE" "$WORK_DIR/$APP_NAME.app"
chflags -R nouchg,noschg "$WORK_DIR/$APP_NAME.app" 2>/dev/null || true
xattr -cr "$WORK_DIR/$APP_NAME.app" 2>/dev/null || true

osascript <<APPLESCRIPT
tell application "Finder"
  set targetFolder to POSIX file "$WORK_DIR" as alias
  set applicationsFolder to POSIX file "/Applications" as alias
  make new alias file to applicationsFolder at targetFolder with properties {name:"Applications"}
end tell
APPLESCRIPT

if [[ -f "$APPLICATIONS_ICON_SOURCE" ]] &&
   command -v sips >/dev/null 2>&1 &&
   command -v DeRez >/dev/null 2>&1 &&
   command -v Rez >/dev/null 2>&1 &&
   command -v SetFile >/dev/null 2>&1; then
  sips -s format png "$APPLICATIONS_ICON_SOURCE" --out "$APPLICATIONS_ICON_PNG" >/dev/null
  sips -i "$APPLICATIONS_ICON_PNG" >/dev/null
  DeRez -only icns "$APPLICATIONS_ICON_PNG" > "$APPLICATIONS_ICON_RSRC"
  Rez -append "$APPLICATIONS_ICON_RSRC" -o "$WORK_DIR/Applications"
  SetFile -a C "$WORK_DIR/Applications"
fi

args=(
  --volname "$VOLUME_NAME"
  --background "$BACKGROUND_PATH"
  --window-pos 120 90
  --window-size 820 460
  --text-size 12
  --icon-size 112
  --icon "$APP_NAME.app" 203 225
  --icon Applications 617 225
  --hide-extension "$APP_NAME.app"
  --no-internet-enable
  --format UDZO
  --filesystem HFS+
  --disk-image-size 700
)

if [[ -n "$SIGN_IDENTITY" ]]; then
  args+=(--codesign "$SIGN_IDENTITY")
fi

create-dmg "${args[@]}" "$DMG_PATH" "$WORK_DIR"
