#!/bin/bash

BUNDLE_ID="com.optiontab.app"
APP_NAME="OptionTab"

echo "Uninstalling $APP_NAME..."

# 1. Reset Accessibility permissions (uninstall_preflight)
echo "Resetting Accessibility permissions..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null

# 2. Quit the app
echo "Quitting $APP_NAME..."
osascript -e "quit app id \"$BUNDLE_ID\"" 2>/dev/null
# Give it a moment to quit gracefully, then force kill if needed
sleep 1
pkill -x "$APP_NAME" 2>/dev/null

# Remove from macOS Login Items
echo "Removing from Login Items..."
osascript -e "tell application \"System Events\" to delete login item \"$APP_NAME\"" 2>/dev/null

# 3. Remove the App bundle itself (Standard uninstall behavior)
echo "Removing App bundle..."
rm -rf "/Applications/$APP_NAME.app"

# 4. Trash UserDefaults and settings (zap trash)
echo "Trashing preferences and settings..."
rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
rm -rf "$HOME/Library/Application Scripts/$BUNDLE_ID"

# Clear defaults domain just to be safe
defaults delete "$BUNDLE_ID" 2>/dev/null

echo "Uninstallation complete!"