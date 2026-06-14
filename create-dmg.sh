#!/bin/bash
set -e

APP_NAME="OptionTab"
VERSION="1.0"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

echo "Building Release version..."
swift build -c release

echo "Assembling App bundle..."
rm -rf "${APP_NAME}.app"
mkdir -p "${APP_NAME}.app/Contents/MacOS"
mkdir -p "${APP_NAME}.app/Contents/Resources"

cp .build/release/${APP_NAME} "${APP_NAME}.app/Contents/MacOS/"
cp Sources/${APP_NAME}/Resources/Info.plist "${APP_NAME}.app/Contents/"
if [ -f "Sources/${APP_NAME}/Resources/AppIcon.icns" ]; then
    cp "Sources/${APP_NAME}/Resources/AppIcon.icns" "${APP_NAME}.app/Contents/Resources/"
fi

echo "Ad-hoc Code signing..."
codesign --force --deep --sign - "${APP_NAME}.app"

echo "Creating DMG..."
rm -f "$DMG_NAME"
create-dmg \
  --volname "${APP_NAME} Installer" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "${APP_NAME}.app" 150 190 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 450 190 \
  "$DMG_NAME" \
  "${APP_NAME}.app"

echo "DMG created: $DMG_NAME"