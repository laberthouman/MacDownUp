#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_PATH="${MACDOWNUP_APP_PATH:-$HOME/Applications/MacDownUp.app}"
STAGED_APP="$BUILD_DIR/MacDownUp.app"
ICONSET="$BUILD_DIR/MacDownUp.iconset"
SOURCE_FILES=("$PROJECT_DIR"/Sources/*.swift)
mkdir -p "$BUILD_DIR" "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"

swiftc "$PROJECT_DIR/Tools/GenerateIcon.swift" -O -framework AppKit -o "$BUILD_DIR/generate-icon"
"$BUILD_DIR/generate-icon" "$ICONSET"
python3 "$PROJECT_DIR/Tools/PackageIcon.py" "$ICONSET" "$STAGED_APP/Contents/Resources/MacDownUp.icns"
cp "$ICONSET/icon_512x512@2x.png" "$STAGED_APP/Contents/Resources/AppIcon.png"
cp -R "$PROJECT_DIR/Resources/Wallpapers" "$STAGED_APP/Contents/Resources/"

for ARCH in arm64 x86_64; do
  echo "Compiling $ARCH (optimized)…"
  swiftc "${SOURCE_FILES[@]}" -parse-as-library -O -whole-module-optimization \
    -target "$ARCH-apple-macos13.0" -framework SwiftUI -framework AppKit \
    -framework Foundation -framework CryptoKit -o "$BUILD_DIR/MacDownUp-$ARCH"
done
lipo -create "$BUILD_DIR/MacDownUp-arm64" "$BUILD_DIR/MacDownUp-x86_64" \
  -output "$STAGED_APP/Contents/MacOS/MacDownUp"
cp "$PROJECT_DIR/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
printf 'APPL????' > "$STAGED_APP/Contents/PkgInfo"
codesign --force --sign - "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
mkdir -p "$(dirname "$APP_PATH")" "$PROJECT_DIR/.backup"
if test -e "$APP_PATH"; then
  mv "$APP_PATH" "$PROJECT_DIR/.backup/MacDownUp-$(date +%Y%m%d-%H%M%S).app"
fi
mv "$STAGED_APP" "$APP_PATH"
echo "Built: $APP_PATH"
