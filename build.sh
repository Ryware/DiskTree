#!/bin/sh
# Build DiskTree.app (release, ad-hoc signed). Usage: ./build.sh [run]
set -e
APP=DiskTree
BUNDLE=build/$APP.app
swift build -c release
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp ".build/release/$APP" "$BUNDLE/Contents/MacOS/$APP"
cp Info.plist "$BUNDLE/Contents/"
cp Assets/AppIcon.icns "$BUNDLE/Contents/Resources/"
codesign --force --deep --sign - "$BUNDLE"
echo "==> $BUNDLE"
[ "$1" = "run" ] && open "$BUNDLE" || true
