#!/bin/sh
# Build, sign (Developer ID + hardened runtime), package as DMG, notarize and staple.
#
# One-time setup:
#   1. Developer ID Application certificate in your login keychain (Xcode → Settings → Accounts → Manage Certificates)
#   2. App-specific password from appleid.apple.com, stored once:
#        xcrun notarytool store-credentials DiskTree --apple-id "<your Apple ID email>" --team-id TEAM_ID_REDACTED --password "<app-specific password>"
#
# Usage: ./release.sh            → dist/DiskTree-<version>.dmg, notarized + stapled
#        ./release.sh --no-notarize
set -e

APP=DiskTree
TEAM_ID=TEAM_ID_REDACTED
NOTARY_PROFILE=DiskTree
BUNDLE=build/$APP.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
DMG=dist/$APP-$VERSION.dmg

# Pick the Developer ID identity for this team automatically.
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($TEAM_ID)" | head -1 | sed -E 's/.*"(.+)".*/\1/')
if [ -z "$IDENTITY" ]; then
  echo "No 'Developer ID Application' certificate for team $TEAM_ID in the keychain." >&2
  echo "Create one in Xcode → Settings → Accounts → Manage Certificates, then re-run." >&2
  exit 1
fi
echo "==> Signing identity: $IDENTITY"

echo "==> Building $APP $VERSION"
./build.sh >/dev/null

echo "==> Signing with hardened runtime"
codesign --force --deep --timestamp --options runtime --sign "$IDENTITY" "$BUNDLE"
codesign --verify --deep --strict --verbose=2 "$BUNDLE"

echo "==> Packaging DMG"
mkdir -p dist
rm -f "$DMG"
STAGING=$(mktemp -d)
cp -R "$BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ "$1" != "--no-notarize" ]; then
  echo "==> Notarizing (this takes a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling"
  xcrun stapler staple "$DMG"
  echo "==> Gatekeeper check"
  spctl -a -vv -t install "$DMG"
fi

echo "==> Done: $DMG"
