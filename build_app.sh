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

echo "🔨 Building $APP_NAME..."
swift build 2>&1

echo "📦 Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# Copy Info.plist into the bundle (required for Accessibility permission)
cp "Sources/OptionTab/Resources/Info.plist" "$CONTENTS/Info.plist"

echo "✅ Done! Run with:"
echo "   open $APP_BUNDLE"
echo ""
echo "   Or to register with Accessibility, open it once:"
echo "   open $APP_BUNDLE"
echo "   Then go to: System Settings → Privacy & Security → Accessibility"
