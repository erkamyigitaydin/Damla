#!/bin/zsh
# Rebuilds MediaRemoteAdapter.framework and the test client from the vendored sources (arm64).
set -e
cd "$(dirname "$0")"
B=MediaRemoteAdapter.framework/Versions/A
rm -rf MediaRemoteAdapter.framework MediaRemoteAdapterTestClient
mkdir -p "$B/Headers" "$B/Resources"
cp include/MediaRemoteAdapter.h "$B/Headers/"
cat > "$B/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
<key>CFBundleName</key><string>MediaRemoteAdapter</string>
<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>0.1.0</string>
</dict></plist>
PLIST
clang -dynamiclib -fobjc-arc -fvisibility=default -Iinclude -Isrc \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name "@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" \
  -o "$B/MediaRemoteAdapter" src/adapter/*.m src/private/MediaRemote.m src/utility/*.m
(cd MediaRemoteAdapter.framework/Versions && ln -sfn A Current)
(cd MediaRemoteAdapter.framework && ln -sfn Versions/Current/MediaRemoteAdapter MediaRemoteAdapter \
  && ln -sfn Versions/Current/Headers Headers && ln -sfn Versions/Current/Resources Resources)
clang -fobjc-arc -framework Foundation -framework MediaPlayer -Isrc/test \
  -o MediaRemoteAdapterTestClient src/test/main.m src/test/NowPlayingTest.m
codesign --force --deep --sign - MediaRemoteAdapter.framework
codesign --force --sign - MediaRemoteAdapterTestClient
echo "built"
