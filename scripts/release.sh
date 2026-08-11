#!/bin/bash
# Cuts a GitHub release with a prebuilt, universal PinballPokedex.app.
#   ./scripts/release.sh v1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?usage: ./scripts/release.sh v1.0.0}"

./build.sh

ARCHS=$(lipo -info PinballPokedex.app/Contents/MacOS/PinballPokedex)
case "$ARCHS" in
    *x86_64*arm64*|*arm64*x86_64*) ;;
    *) echo "refusing to release a non-universal build: $ARCHS" >&2; exit 1 ;;
esac

# ditto (not zip) so the bundle's symlinks and extended attributes survive the round trip.
ZIP="PinballPokedex-${TAG}-universal.zip"
rm -f "$ZIP"
ditto -c -k --keepParent PinballPokedex.app "$ZIP"

gh release create "$TAG" "$ZIP" \
    --title "Pinball Pokédex ${TAG}" \
    --notes-file - <<EOF
Universal build (Apple Silicon + Intel), macOS 13 or later.

**Install:** unzip, drag \`PinballPokedex.app\` to /Applications, then run this once:

\`\`\`bash
xattr -dr com.apple.quarantine /Applications/PinballPokedex.app
\`\`\`

The app is ad-hoc signed rather than notarized (that needs a paid Apple Developer
account), so macOS quarantines it on download and will otherwise refuse to open it.
The command above clears that flag. You can inspect every line of what you're running
in this repo.

See the README for connecting the live mGBA bridge.
EOF

echo "released $TAG"
rm -f "$ZIP"
