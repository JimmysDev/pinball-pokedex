#!/bin/bash
# Builds, signs, notarizes and publishes a release.
#   ./scripts/release.sh v1.0.1
#
# One-time setup (you run this yourself — it asks for an Apple ID app-specific password,
# generated at appleid.apple.com ▸ Sign-In and Security ▸ App-Specific Passwords):
#
#   xcrun notarytool store-credentials pinball-pokedex \
#       --apple-id <your-apple-id> --team-id R278L22M37
#
# That stores the password in your keychain; nothing secret is ever written to this repo.
#
# Note that build.sh deliberately stays ad-hoc signed so anyone can clone and build without
# a Developer ID. Real signing happens here, at release time, only.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?usage: ./scripts/release.sh v1.0.0}"
PROFILE="${NOTARY_PROFILE:-pinball-pokedex}"
APP="PinballPokedex.app"

SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
[ -n "$SIGN_ID" ] || { echo "no Developer ID Application certificate in the keychain" >&2; exit 1; }

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    cat >&2 <<EOF
No notarytool keychain profile named "$PROFILE".

Run this yourself (it will prompt for an app-specific password):

  xcrun notarytool store-credentials $PROFILE \\
      --apple-id <your-apple-id> --team-id R278L22M37

EOF
    exit 1
fi

./build.sh

ARCHS=$(lipo -info "$APP/Contents/MacOS/PinballPokedex")
case "$ARCHS" in
    *x86_64*arm64*|*arm64*x86_64*) ;;
    *) echo "refusing to release a non-universal build: $ARCHS" >&2; exit 1 ;;
esac

echo "▸ signing with: $SIGN_ID"
# --options runtime is the hardened runtime, which notarization requires; --timestamp gets a
# trusted timestamp so the signature stays valid after the certificate expires.
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

ZIP="PinballPokedex-${TAG}-universal.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"      # ditto, not zip: preserves bundle structure

echo "▸ notarizing (usually a minute or two)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

# Staple the ticket into the app so it launches even offline, then re-zip the stapled copy.
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Gatekeeper verdict:"
spctl -a -vvv -t install "$APP"

gh release create "$TAG" "$ZIP" \
    --title "Pinball Pokédex ${TAG}" \
    --notes-file - <<EOF
Universal build (Apple Silicon + Intel), macOS 13 or later.

**Install:** unzip and drag \`PinballPokedex.app\` to /Applications. That's it — the app is
signed with a Developer ID and notarized by Apple, so it opens normally with no security
warnings and no terminal commands.

See the README for connecting the live mGBA bridge.
EOF

echo "released $TAG"
rm -f "$ZIP"
