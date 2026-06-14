#!/bin/bash
# build_app.sh — Builds OptionTab.app bundle from Swift Package

set -e

APP_NAME="OptionTab"
BUNDLE_ID="com.optiontab.app"
BUILD_DIR=".build/debug"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

# Kill any running instance first
killall "$APP_NAME" 2>/dev/null || true
sleep 0.5

echo "Building $APP_NAME..."
swift build 2>&1

echo "Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# Copy Info.plist into the bundle (required for Accessibility permission)
cp "Sources/OptionTab/Resources/Info.plist" "$CONTENTS/Info.plist"

# Copy App Icon if it exists
if [ -f "Sources/OptionTab/Resources/AppIcon.icns" ]; then
    cp "Sources/OptionTab/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Ad-hoc code sign — required for CGEvent tap to work on modern macOS
echo "Code signing..."
codesign --force --sign - --deep "$APP_BUNDLE"

echo "Done! Run with:"
echo "   open $APP_BUNDLE"
echo ""
echo "To see diagnostic logs:"
echo "   ./$APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo ""
echo "After rebuilding, remove and re-add OptionTab in:"
echo "   System Settings -> Privacy & Security -> Accessibility"
