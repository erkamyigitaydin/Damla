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
# Now Playing adapter (perl-hosted MediaRemote bridge); bundled, never linked.
ADAPTER_SRC="$PROJECT_DIR/Vendor/MediaRemoteAdapter"
ADAPTER_DST="$APP_DIR/Contents/Resources/MediaRemoteAdapter"
rm -rf "$ADAPTER_DST"; mkdir -p "$ADAPTER_DST"
cp -R "$ADAPTER_SRC/MediaRemoteAdapter.framework" "$ADAPTER_DST/"
cp "$ADAPTER_SRC/MediaRemoteAdapterTestClient" "$ADAPTER_SRC/mediaremote-adapter.pl" "$ADAPTER_SRC/LICENSE" "$ADAPTER_DST/"
# Sign with a stable identity so TCC permissions (Accessibility, Automation) survive rebuilds.
# Override with DAMLA_SIGN_IDENTITY; falls back to the first Apple Development certificate, then ad-hoc.
IDENTITY="${DAMLA_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')"
fi
[[ -z "$IDENTITY" ]] && IDENTITY="-"
codesign --force --sign "$IDENTITY" --timestamp=none "$ADAPTER_DST/MediaRemoteAdapter.framework"
codesign --force --sign "$IDENTITY" --timestamp=none "$ADAPTER_DST/MediaRemoteAdapterTestClient"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
printf 'Signed with: %s\n' "$IDENTITY"
"$APP_DIR/Contents/MacOS/Damla" --self-test
printf 'Built: %s\n' "$APP_DIR"
