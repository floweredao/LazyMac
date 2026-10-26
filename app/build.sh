#!/bin/zsh
# Build LazyMac.app (universal: Apple Silicon and Intel) into app/build/ and zip it for a release.
# Usage: app/build.sh   -> app/build/LazyMac.app and app/build/LazyMac-<VERSION>.zip
set -euo pipefail
APP=${0:A:h}
VERSION=$(<"$APP/VERSION")
OUT=$APP/build
rm -rf "$OUT"
mkdir -p "$OUT"
cd "$APP"

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/lazymac

BUNDLE=$OUT/LazyMac.app
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/lazymac"
cp "$APP/../bin/nogit-backup.sh" "$BUNDLE/Contents/Resources/nogit-backup.sh"
cp "$APP/../bin/due.sh" "$BUNDLE/Contents/Resources/due.sh"
# The scripts the app runs (Tools.codeRoot): a new Mac has no LazyMac repo, so the app carries them.
mkdir -p "$BUNDLE/Contents/Resources/bin"
cp -p "$APP"/../bin/*.(sh|ts|html) "$BUNDLE/Contents/Resources/bin/"
cp -Rp "$APP/../launchd" "$APP/../example" "$APP/../.gitleaks.toml" "$BUNDLE/Contents/Resources/"
sed "s/__VERSION__/$VERSION/g" "$APP/Info.plist" > "$BUNDLE/Contents/Info.plist"
swift "$APP/icon.swift" "$OUT/lazymac.iconset"
iconutil -c icns "$OUT/lazymac.iconset" -o "$BUNDLE/Contents/Resources/lazymac.icns"
rm -rf "$OUT/lazymac.iconset"
codesign --force --deep --sign - "$BUNDLE"
ditto -c -k --keepParent "$BUNDLE" "$OUT/LazyMac-$VERSION.zip"
print "built $BUNDLE and $OUT/LazyMac-$VERSION.zip (version $VERSION)"
