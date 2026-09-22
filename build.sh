#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
BUILD_DIR="${DAMLA_BUILD_DIR:-$PROJECT_DIR/.build}"
APP_DIR="$PROJECT_DIR/../Damla.app"
BUILD_FLAGS=(--disable-sandbox --cache-path "$BUILD_DIR/cache" --config-path "$BUILD_DIR/config" --security-path "$BUILD_DIR/security" --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR" -c release -debug-info-format none)
swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Damla" "$APP_DIR/Contents/MacOS/Damla"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
"$APP_DIR/Contents/MacOS/Damla" --self-test
printf 'Built: %s\n' "$APP_DIR"
