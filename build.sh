#!/bin/bash
# Builds Pinball Pokédex into ./PinballPokedex.app
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate
# ARCHS is set on the command line too: an incremental build will otherwise happily reuse a
# single-arch binary from a previous run and quietly ship an Apple-Silicon-only app.
xcodebuild -project PinballPokedex.xcodeproj -scheme PinballPokedex \
    -configuration Release -derivedDataPath build \
    ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO build

APP="build/Build/Products/Release/PinballPokedex.app"
codesign --force -s - "$APP" 2>/dev/null || true   # ad-hoc sign for cleaner local launch

rm -rf PinballPokedex.app
cp -R "$APP" PinballPokedex.app
echo "✅ Built ./PinballPokedex.app  (double-click to run, or drag to /Applications)"
