#!/bin/zsh
# Builds a shareable Damla: universal binary, Developer ID signature with hardened runtime,
# notarized and stapled .dmg. Needs (once) a "Developer ID Application" certificate in Keychain and
# `xcrun notarytool store-credentials damla-notary --team-id <TEAM>`.
#
#   zsh release.sh            # build + sign + notarize + dmg   → dist/Damla-<version>.dmg
#   zsh release.sh --no-notarize   # sign only (for a quick local check)
set -euo pipefail
PROJECT_DIR="${0:A:h}"
BUILD_DIR="${DAMLA_BUILD_DIR:-$PROJECT_DIR/.build}"
DIST="$PROJECT_DIR/dist"
APP="$DIST/Damla.app"
PROFILE="${DAMLA_NOTARY_PROFILE:-damla-notary}"
NOTARIZE=1
[[ "${1:-}" == "--no-notarize" ]] && NOTARIZE=0

IDENTITY="${DAMLA_RELEASE_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}"
if [[ -z "$IDENTITY" ]]; then
  echo "Developer ID Application sertifikası bulunamadı. Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application." >&2
  exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")"
echo "→ sürüm $VERSION, imza: $IDENTITY"

echo "→ evrensel derleme (arm64 + x86_64)"
FLAGS=(--disable-sandbox --cache-path "$BUILD_DIR/cache" --config-path "$BUILD_DIR/config" --security-path "$BUILD_DIR/security"
       --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR" -c release -debug-info-format none --arch arm64 --arch x86_64)
swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/Damla"
lipo -archs "$BIN"

echo "→ paket"
rm -rf "$APP" "$DIST/dmg-root"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Damla"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
[[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]] && cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/"
ADAPTER_SRC="$PROJECT_DIR/Vendor/MediaRemoteAdapter"
ADAPTER_DST="$APP/Contents/Resources/MediaRemoteAdapter"
mkdir -p "$ADAPTER_DST"
cp -R "$ADAPTER_SRC/MediaRemoteAdapter.framework" "$ADAPTER_DST/"
cp "$ADAPTER_SRC/MediaRemoteAdapterTestClient" "$ADAPTER_SRC/mediaremote-adapter.pl" "$ADAPTER_SRC/LICENSE" "$ADAPTER_DST/"
if [[ "$(lipo -archs "$ADAPTER_DST/MediaRemoteAdapter.framework/MediaRemoteAdapter")" != *x86_64* ]]; then
  echo "  not: Now Playing adaptörü yalnızca arm64; Intel Mac'te Apple Events yedeği devreye girer (evrensel için: zsh Vendor/MediaRemoteAdapter/build-adapter.sh --universal)"
fi

echo "→ imza (hardened runtime, zaman damgası)"
SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
"${SIGN[@]}" "$ADAPTER_DST/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter"
"${SIGN[@]}" "$ADAPTER_DST/MediaRemoteAdapter.framework"
"${SIGN[@]}" "$ADAPTER_DST/MediaRemoteAdapterTestClient"
"${SIGN[@]}" --entitlements "$PROJECT_DIR/Resources/Damla.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
"$APP/Contents/MacOS/Damla" --self-test

echo "→ dmg"
DMG="$DIST/Damla-$VERSION.dmg"
rm -f "$DMG"; mkdir -p "$DIST/dmg-root"
cp -R "$APP" "$DIST/dmg-root/"
ln -s /Applications "$DIST/dmg-root/Applications"
hdiutil create -volname "Damla $VERSION" -srcfolder "$DIST/dmg-root" -ov -format UDZO -quiet "$DMG"
rm -rf "$DIST/dmg-root"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if (( NOTARIZE )); then
  echo "→ noter onayı (Apple'a gönderiliyor, genelde 1-5 dk)"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
  spctl --assess --type open --context context:primary-signature -v "$DMG" 2>&1 | tail -1
fi
printf '\nHazır: %s\n' "$DMG"
