#!/bin/sh
# Builds Release and installs to /Applications. The login item and the greedify:// URL
# handler are tied to the app's location, so always run the installed copy.
set -eu
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Greedify.xcodeproj -scheme Greedify -configuration Release -derivedDataPath build build | tail -3
pkill -x Greedify 2>/dev/null || true
rm -rf /Applications/Greedify.app
cp -R build/Build/Products/Release/Greedify.app /Applications/
open /Applications/Greedify.app
