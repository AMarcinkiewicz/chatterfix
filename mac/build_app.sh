#!/bin/bash
# Builds ChatterFix.app as a universal (Apple Silicon + Intel) binary.
# Run:  ./build_app.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "Compiling ChatterFix (universal: arm64 + x86_64)..."
swiftc -O -target arm64-apple-macos13.0 \
    ChatterFixApp.swift -o ChatterFix_arm64 -framework Cocoa
swiftc -O -target x86_64-apple-macos13.0 \
    ChatterFixApp.swift -o ChatterFix_x86_64 -framework Cocoa
lipo -create ChatterFix_arm64 ChatterFix_x86_64 -output ChatterFix_exec
rm -f ChatterFix_arm64 ChatterFix_x86_64

if [ ! -f AppIcon.icns ]; then
    echo "Generating app icon..."
    swiftc -O make_icon.swift -o make_icon_exec -framework Cocoa
    ./make_icon_exec icon_1024.png
    rm -rf AppIcon.iconset
    mkdir AppIcon.iconset
    for size in 16 32 128 256 512; do
        sips -z $size $size icon_1024.png \
            --out "AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double icon_1024.png \
            --out "AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    rm -rf AppIcon.iconset icon_1024.png make_icon_exec
fi

echo "Assembling ChatterFix.app..."
rm -rf ChatterFix.app
mkdir -p ChatterFix.app/Contents/MacOS ChatterFix.app/Contents/Resources
cp Info.plist ChatterFix.app/Contents/
mv ChatterFix_exec ChatterFix.app/Contents/MacOS/ChatterFix
cp AppIcon.icns ChatterFix.app/Contents/Resources/

# Ad-hoc signature. This is NOT a Developer ID signature (downloads still show
# Gatekeeper's "unverified developer" prompt), but Apple Silicon refuses to run
# a completely unsigned binary, so this is required for the app to launch at all.
codesign --force --deep --sign - ChatterFix.app

echo "Universal binary architectures:"
lipo -info ChatterFix.app/Contents/MacOS/ChatterFix
echo "Done: ChatterFix.app"
