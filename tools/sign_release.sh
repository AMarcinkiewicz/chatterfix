#!/bin/bash
# Builds and signs docs/appcast.json, the manifest the apps check for updates.
#
# Usage: ./tools/sign_release.sh 1.0.1 [path/to/ChatterFix.dmg] [path/to/ChatterFix.exe]
#
# The apps verify the signature with a public key compiled into them, so a
# tampered manifest (or one pointing at a swapped binary) is rejected. Run this
# after uploading the release assets to GitHub, then commit docs/appcast.json.
set -euo pipefail
cd "$(dirname "$0")/.."

KEY="${CHATTERFIX_KEY:-$HOME/.chatterfix/release_private.pem}"
VERSION="${1:-}"
DMG="${2:-mac/ChatterFix.dmg}"
EXE="${3:-windows/ChatterFix.exe}"
REPO="AMarcinkiewicz/chatterfix"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version> [dmg] [exe]   e.g. $0 1.0.1"; exit 1
fi
if [ ! -f "$KEY" ]; then
    echo "Signing key not found at $KEY"
    echo "Set CHATTERFIX_KEY or restore your backup — releases cannot be signed without it."
    exit 1
fi
for f in "$DMG" "$EXE"; do
    [ -f "$f" ] || { echo "Missing artifact: $f"; exit 1; }
done

BASE="https://github.com/$REPO/releases/download/v$VERSION"
MAC_URL="$BASE/ChatterFix.dmg"
WIN_URL="$BASE/ChatterFix.exe"
MAC_SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
WIN_SHA=$(shasum -a 256 "$EXE" | cut -d' ' -f1)
MAC_SIZE=$(wc -c < "$DMG" | tr -d ' ')
WIN_SIZE=$(wc -c < "$EXE" | tr -d ' ')
NOTES="https://github.com/$REPO/releases/tag/v$VERSION"

# Canonical payload: the exact bytes both apps reconstruct and verify against.
# Field order is fixed and must never change without bumping the apps.
PAYLOAD=$(printf '%s\n%s\n%s\n%s\n%s\n%s' \
    "$VERSION" "$MAC_URL" "$MAC_SHA" "$WIN_URL" "$WIN_SHA" "$NOTES")

SIG=$(printf '%s' "$PAYLOAD" | openssl dgst -sha256 -sign "$KEY" | base64 | tr -d '\n')

cat > docs/appcast.json <<JSON
{
  "version": "$VERSION",
  "notesUrl": "$NOTES",
  "mac": {
    "url": "$MAC_URL",
    "sha256": "$MAC_SHA",
    "size": $MAC_SIZE
  },
  "win": {
    "url": "$WIN_URL",
    "sha256": "$WIN_SHA",
    "size": $WIN_SIZE
  },
  "signature": "$SIG"
}
JSON

echo "Wrote docs/appcast.json for $VERSION"
echo "  mac  $MAC_SHA  ($MAC_SIZE bytes)"
echo "  win  $WIN_SHA  ($WIN_SIZE bytes)"

# Verify what we just wrote, so a broken manifest never reaches users.
printf '%s' "$PAYLOAD" > /tmp/cf_payload.$$
printf '%s' "$SIG" | base64 --decode > /tmp/cf_sig.$$
openssl dgst -sha256 -verify <(openssl rsa -in "$KEY" -pubout 2>/dev/null) \
    -signature /tmp/cf_sig.$$ /tmp/cf_payload.$$
rm -f /tmp/cf_payload.$$ /tmp/cf_sig.$$
echo "Commit docs/appcast.json and push to publish the update."
