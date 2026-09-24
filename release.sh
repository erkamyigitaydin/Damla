#!/bin/zsh
# Builds a shareable Damla: universal binary, Developer ID signature with hardened runtime,
# notarized and stapled .dmg. Needs (once) a "Developer ID Application" certificate in Keychain and
# `xcrun notarytool store-credentials damla-notary --team-id <TEAM>`.
#
#   zsh release.sh                 # build + sign + notarize + dmg + appcast + GitHub Release
#   zsh release.sh --no-notarize   # sign only (for a quick local check; no appcast, no release)
#   zsh release.sh --no-publish    # everything except the appcast commit and the GitHub Release
# Updates: the dmg is also signed with the Sparkle EdDSA key from Keychain (generate_keys) and an entry
# is appended to appcast.xml, which is committed and pushed; the dmg becomes a GitHub Release asset.
set -euo pipefail
PROJECT_DIR="${0:A:h}"
BUILD_DIR="${DAMLA_BUILD_DIR:-$PROJECT_DIR/.build}"
DIST="$PROJECT_DIR/dist"
APP="$DIST/Damla.app"
PROFILE="${DAMLA_NOTARY_PROFILE:-damla-notary}"
NOTARIZE=1; PUBLISH=1
[[ "${1:-}" == "--no-notarize" ]] && { NOTARIZE=0; PUBLISH=0; }
[[ "${1:-}" == "--no-publish" ]] && PUBLISH=0
REPO="erkamyigitaydin/Damla"

IDENTITY="${DAMLA_RELEASE_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}"
if [[ -z "$IDENTITY" ]]; then
  echo "Developer ID Application sertifikası bulunamadı. Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application." >&2
  exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PROJECT_DIR/Resources/Info.plist")"
echo "→ sürüm $VERSION ($BUILD), imza: $IDENTITY"
if (( PUBLISH )); then
  [[ -z "$(git -C "$PROJECT_DIR" status --porcelain)" ]] || { echo "Çalışma ağacı temiz değil; önce commit at." >&2; exit 1; }
  gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1 && { echo "v$VERSION zaten yayında; Info.plist'te sürümü artır." >&2; exit 1; }
fi

echo "→ evrensel derleme (arm64 + x86_64)"
FLAGS=(--disable-sandbox --cache-path "$BUILD_DIR/cache" --config-path "$BUILD_DIR/config" --security-path "$BUILD_DIR/security"
       --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR" -c release -debug-info-format none --arch arm64 --arch x86_64)
swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/Damla"
lipo -archs "$BIN"

echo "→ paket"
rm -rf "$APP" "$DIST/dmg-root"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
SPARKLE="$(find "$BUILD_DIR/artifacts" -type d -name "Sparkle.framework" -path "*macos-arm64_x86_64*" | head -1)"
[[ -n "$SPARKLE" ]] || { echo "Sparkle.framework bulunamadı" >&2; exit 1; }
cp -R "$SPARKLE" "$APP/Contents/Frameworks/"
SPARKLE_BIN="$(dirname "$(find "$BUILD_DIR/artifacts" -type f -name sign_update -not -path "*old_dsa*" | head -1)")"
cp "$BIN" "$APP/Contents/MacOS/Damla"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
[[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]] && cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/"
for lproj in "$PROJECT_DIR"/Resources/*.lproj; do cp -R "$lproj" "$APP/Contents/Resources/"; done
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
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for item in "$FW/XPCServices/"*.xpc "$FW/Autoupdate" "$FW/Updater.app"; do [[ -e "$item" ]] && "${SIGN[@]}" "$item"; done
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
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

if (( PUBLISH )); then
  echo "→ appcast (EdDSA imzası Keychain'deki Sparkle anahtarıyla)"
  SIG="$("$SPARKLE_BIN/sign_update" "$DMG" 2>&1)"   # sparkle:edSignature="…" length="…"
  ED="$(printf '%s' "$SIG" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
  LEN="$(printf '%s' "$SIG" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
  [[ -n "$ED" && -n "$LEN" ]] || { echo "sign_update başarısız: $SIG" >&2; exit 1; }
  URL="https://github.com/$REPO/releases/download/v$VERSION/Damla-$VERSION.dmg"
  NOTES_FILE="$PROJECT_DIR/dist/notes-$VERSION.md"
  [[ -f "$NOTES_FILE" ]] || git -C "$PROJECT_DIR" log -1 --format='%B' > "$NOTES_FILE"
  python3 "$PROJECT_DIR/scripts/appcast.py" "$PROJECT_DIR/appcast.xml" --version "$VERSION" --build "$BUILD" \
    --url "$URL" --length "$LEN" --signature "$ED" --notes "$NOTES_FILE" --min-os 26.0
  echo "→ GitHub Release v$VERSION"
  gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "Damla $VERSION" --notes-file "$NOTES_FILE"
  git -C "$PROJECT_DIR" add appcast.xml
  git -C "$PROJECT_DIR" commit -q -m "appcast: $VERSION"
  git -C "$PROJECT_DIR" push -q origin main
  echo "→ yayında: https://github.com/$REPO/releases/tag/v$VERSION"
fi
printf '\nHazır: %s\n' "$DMG"
