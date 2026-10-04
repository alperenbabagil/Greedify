#!/bin/sh
# Builds a downloadable Release zip for GitHub Releases: build/release/Greedify-<version>.zip.
# Signed ad-hoc whatever Local.xcconfig says (no Developer ID, and no developer's name in the signature), and
# arm64 only: Homebrew's librespot is built for this Mac's architecture alone.
set -eu
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Greedify.xcodeproj -scheme Greedify -configuration Release -derivedDataPath build/package \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build | tail -1
APP=build/package/Build/Products/Release/Greedify.app
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="build/release/Greedify-$VERSION.zip"
mkdir -p build/release
rm -f "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"
echo "$OUT"
shasum -a 256 "$OUT"
