#!/bin/bash
# Builds Pinball Pokédex into ./PinballPokedex.app
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate
xcodebuild -project PinballPokedex.xcodeproj -scheme PinballPokedex \
    -configuration Release -derivedDataPath build build

APP="build/Build/Products/Release/PinballPokedex.app"
codesign --force -s - "$APP" 2>/dev/null || true   # ad-hoc sign for cleaner local launch

rm -rf PinballPokedex.app
cp -R "$APP" PinballPokedex.app
echo "✅ Built ./PinballPokedex.app  (double-click to run, or drag to /Applications)"
