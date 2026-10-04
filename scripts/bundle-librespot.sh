#!/bin/sh
# Xcode post-build step: copies Homebrew's librespot, the launcher and the event script into Greedify.app
# and signs the nested executables so the app signature stays valid.
set -eu
SRC="${LIBRESPOT_BIN:-}"
if [ -z "$SRC" ]; then
  for candidate in /opt/homebrew/bin/librespot /usr/local/bin/librespot; do
    [ -x "$candidate" ] && SRC="$candidate" && break
  done
fi
if [ -z "$SRC" ] || [ ! -x "$SRC" ]; then
  echo "error: librespot not found. Run: brew install librespot (or set LIBRESPOT_BIN)" >&2
  exit 1
fi
MACOS_DIR="$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH"
cp -f "$(realpath "$SRC")" "$MACOS_DIR/librespot"
cp -f "$SRCROOT/App/Resources/greedify-speaker" "$MACOS_DIR/greedify-speaker"
cp -f "$SRCROOT/App/Resources/greedify-event" "$MACOS_DIR/greedify-event"
# librespot is MIT-licensed: its notice travels with every copy of the app.
LICENSE="$(dirname "$(realpath "$SRC")")/../LICENSE"
[ -f "$LICENSE" ] && cp -f "$LICENSE" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/librespot-LICENSE"
chmod 755 "$MACOS_DIR/librespot" "$MACOS_DIR/greedify-speaker" "$MACOS_DIR/greedify-event"
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$MACOS_DIR/librespot" "$MACOS_DIR/greedify-speaker" "$MACOS_DIR/greedify-event"
