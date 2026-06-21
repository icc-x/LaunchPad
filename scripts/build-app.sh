#!/bin/bash
# LaunchPad .app Bundle Builder
# Usage: ./scripts/build-app.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_BUNDLE="$PROJECT_DIR/.build/LaunchPad.app"

echo "Building LaunchPadApp (release)..."
cd "$PROJECT_DIR"
swift build -c release --product LaunchPadApp

echo "Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/LaunchPadApp" "$APP_BUNDLE/Contents/MacOS/LaunchPadApp"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "Done: $APP_BUNDLE"
echo "Run:  open $APP_BUNDLE"
