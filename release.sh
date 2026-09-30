#!/bin/sh
# Build, sign (Developer ID + hardened runtime), package as DMG, notarize and staple.
#
# One-time setup:
#   1. Developer ID Application certificate in your login keychain
#      (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application).
#   2. Notarization credentials, either:
#        a. an App Store Connect API key in .secrets/ (ASC_KEY_ID + ASC_ISSUER_ID below), or
#        b. a keychain profile:  xcrun notarytool store-credentials DiskTree --apple-id ... --team-id W9J3HSY24R
#
# Usage: ./release.sh            → dist/DiskTree-<version>.dmg, notarized + stapled
#        ./release.sh --no-notarize
set -e
cd "$(dirname "$0")"

APP=DiskTree
TEAM_ID=W9J3HSY24R
NOTARY_PROFILE=DiskTree
ASC_KEY_ID=${ASC_KEY_ID:-XL6AR5TLSY}
ASC_ISSUER_ID=${ASC_ISSUER_ID:-69cf28d6-a264-4aac-9189-8d69b9657f6e}
ASC_KEY_PATH=${ASC_KEY_PATH:-.secrets/AuthKey_$ASC_KEY_ID.p8}
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
./build.sh

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
  if [ -f "$ASC_KEY_PATH" ]; then
    xcrun notarytool submit "$DMG" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
  else
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  fi
  echo "==> Stapling"
  xcrun stapler staple "$DMG"
  echo "==> Gatekeeper check"
  spctl -a -vv -t install "$DMG"
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "==> Done: $DMG"
