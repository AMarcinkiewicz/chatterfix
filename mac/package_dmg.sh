#!/bin/bash
# Packages ChatterFix.app into a distributable .dmg with a drag-to-Applications
# layout. Run after build_app.sh.  Usage: ./package_dmg.sh
set -euo pipefail
cd "$(dirname "$0")"

# Name matches what the site links to; the release tag carries the version.
DMG="ChatterFix.dmg"

if [ ! -d ChatterFix.app ]; then
    echo "ChatterFix.app not found — run ./build_app.sh first."
    exit 1
fi

STAGE="$(mktemp -d)"
cp -R ChatterFix.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# The Commons Clause requires the licence notice to travel with every copy.
cp ../LICENSE "$STAGE/LICENSE.txt"

rm -f "$DMG"
hdiutil create -volname "ChatterFix" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "Built $DMG"
du -h "$DMG"
