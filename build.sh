#!/bin/sh
# Build DiskTree.app (release, universal, ad-hoc signed). Usage: ./build.sh [run]
set -e
APP=DiskTree
BUNDLE=build/$APP.app
# Universal binary so the direct-download build runs on Apple silicon and Intel Macs.
swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN/$APP" "$BUNDLE/Contents/MacOS/$APP"
cp Info.plist "$BUNDLE/Contents/"
cp Assets/AppIcon.icns "$BUNDLE/Contents/Resources/"
codesign --force --deep --sign - "$BUNDLE"
echo "==> $BUNDLE ($(lipo -archs "$BUNDLE/Contents/MacOS/$APP"))"
[ "$1" = "run" ] && open "$BUNDLE" || true
