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
# Sparkle (auto-updates): SwiftPM fetches the framework; it has to be embedded by hand.
SPARKLE="$(find "$BUILD_DIR/artifacts" -type d -name "Sparkle.framework" -path "*macos-arm64_x86_64*" | head -1)"
if [[ -z "$SPARKLE" ]]; then echo "Sparkle.framework bulunamadı (swift build artifacts)"; exit 1; fi
rm -rf "$APP_DIR/Contents/Frameworks"; mkdir -p "$APP_DIR/Contents/Frameworks"
cp -R "$SPARKLE" "$APP_DIR/Contents/Frameworks/"
# Now Playing adapter (perl-hosted MediaRemote bridge); bundled, never linked.
ADAPTER_SRC="$PROJECT_DIR/Vendor/MediaRemoteAdapter"
ADAPTER_DST="$APP_DIR/Contents/Resources/MediaRemoteAdapter"
rm -rf "$ADAPTER_DST"; mkdir -p "$ADAPTER_DST"
cp -R "$ADAPTER_SRC/MediaRemoteAdapter.framework" "$ADAPTER_DST/"
cp "$ADAPTER_SRC/MediaRemoteAdapterTestClient" "$ADAPTER_SRC/mediaremote-adapter.pl" "$ADAPTER_SRC/LICENSE" "$ADAPTER_DST/"
# Sign with the same identity as release.sh (Developer ID) so TCC permissions (Accessibility, Automation)
# survive both rebuilds and Sparkle updates: macOS ties a grant to the signing identity, and a dev build
# signed with another certificate loses it the moment an update replaces the bundle.
# Override with DAMLA_SIGN_IDENTITY; falls back to Apple Development, then ad-hoc.
IDENTITY="${DAMLA_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')"
fi
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')"
fi
[[ -z "$IDENTITY" ]] && IDENTITY="-"
FW="$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B"
for item in "$FW/XPCServices/"*.xpc "$FW/Autoupdate" "$FW/Updater.app" "$APP_DIR/Contents/Frameworks/Sparkle.framework"; do
  [[ -e "$item" ]] && codesign --force --sign "$IDENTITY" --timestamp=none "$item"
done
codesign --force --sign "$IDENTITY" --timestamp=none "$ADAPTER_DST/MediaRemoteAdapter.framework"
codesign --force --sign "$IDENTITY" --timestamp=none "$ADAPTER_DST/MediaRemoteAdapterTestClient"
# Hardened runtime and entitlements as in release.sh, so signing problems show up before a release does.
codesign --force --sign "$IDENTITY" --timestamp=none --options runtime --entitlements "$PROJECT_DIR/Resources/Damla.entitlements" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
printf 'Signed with: %s\n' "$IDENTITY"
"$APP_DIR/Contents/MacOS/Damla" --self-test
printf 'Built: %s\n' "$APP_DIR"
