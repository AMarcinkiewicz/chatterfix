#!/bin/bash
# Packages ChatterFix.app into a distributable .dmg with a drag-to-Applications
# layout. Run after build_app.sh.  Usage: ./package_dmg.sh [version]
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-1.0.0}"
DMG="ChatterFix-${VERSION}-macOS.dmg"

if [ ! -d ChatterFix.app ]; then
    echo "ChatterFix.app not found — run ./build_app.sh first."
    exit 1
fi

STAGE="$(mktemp -d)"
cp -R ChatterFix.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "ChatterFix" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "Built $DMG"
du -h "$DMG"
