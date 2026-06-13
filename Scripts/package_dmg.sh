#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/DerivedData}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Kara.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Kara/Supporting/Info.plist)"
DMG_PATH="dist/Kara-$VERSION.dmg"
DMG_ROOT="build/dmg-root"

xcodebuild \
  -project Kara.xcodeproj \
  -scheme Kara \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_IDENTITY="-" \
  build

rm -rf "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT" dist
cp -R "$APP_PATH" "$DMG_ROOT/Kara.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname Kara \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
