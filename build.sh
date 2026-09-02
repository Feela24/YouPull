#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/config.sh"

BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Chybí Xcode Command Line Tools. Nainstaluj je příkazem: xcode-select --install"
  exit 1
fi

# Standalone build must carry every runtime tool inside the .app bundle.
if [[ ! -x "$ROOT/Resources/bin/yt-dlp" || \
      ! -x "$ROOT/Resources/bin/arm64/ffmpeg" || \
      ! -x "$ROOT/Resources/bin/arm64/ffprobe" || \
      ! -x "$ROOT/Resources/bin/x86_64/ffmpeg" || \
      ! -x "$ROOT/Resources/bin/x86_64/ffprobe" ]]; then
  echo "Standalone nástroje zatím nejsou stažené."
  "$ROOT/scripts/fetch-standalone-tools.sh"
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET_ARM64="arm64-apple-macos13.0"
TARGET_X64="x86_64-apple-macos13.0"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES/bin" "$RESOURCES/licenses"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

PLIST="$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE_NAME" "$PLIST"

# Ikona: použij vlastní Resources/AppIcon.icns. Pokud chybí, build vytvoří
# výchozí modrou download ikonu, takže Finder i Dock neukážou generickou ikonu.
ICON_TO_COPY="$ROOT/Resources/AppIcon.icns"
if [[ ! -f "$ICON_TO_COPY" ]]; then
  DEFAULT_PNG="$BUILD/OpenPull-default-icon-1024.png"
  DEFAULT_ICONSET="$BUILD/OpenPull-default.iconset"
  DEFAULT_ICNS="$BUILD/OpenPull-default.icns"

  echo "Vytvářím výchozí ikonu aplikace…"
  xcrun --sdk macosx swift "$ROOT/scripts/generate-default-icon.swift" "$DEFAULT_PNG"
  rm -rf "$DEFAULT_ICONSET"
  mkdir -p "$DEFAULT_ICONSET"

  sips -z 16 16 "$DEFAULT_PNG" --out "$DEFAULT_ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$DEFAULT_PNG" --out "$DEFAULT_ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$DEFAULT_PNG" --out "$DEFAULT_ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$DEFAULT_PNG" --out "$DEFAULT_ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$DEFAULT_PNG" --out "$DEFAULT_ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$DEFAULT_PNG" --out "$DEFAULT_ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$DEFAULT_PNG" --out "$DEFAULT_ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$DEFAULT_PNG" --out "$DEFAULT_ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$DEFAULT_PNG" --out "$DEFAULT_ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$DEFAULT_PNG" --out "$DEFAULT_ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$DEFAULT_ICONSET" -o "$DEFAULT_ICNS"
  ICON_TO_COPY="$DEFAULT_ICNS"
fi

cp "$ICON_TO_COPY" "$RESOURCES/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.icns" "$PLIST"

# Přibal všechny runtime nástroje a jejich licenční informace.
cp -R "$ROOT/Resources/bin/." "$RESOURCES/bin/"
if [[ -d "$ROOT/Resources/licenses" ]]; then
  cp -R "$ROOT/Resources/licenses/." "$RESOURCES/licenses/"
fi
cp "$ROOT/Resources/THIRD_PARTY_NOTICES.txt" "$RESOURCES/THIRD_PARTY_NOTICES.txt"
chmod +x "$RESOURCES/bin/yt-dlp" \
  "$RESOURCES/bin/arm64/ffmpeg" "$RESOURCES/bin/arm64/ffprobe" \
  "$RESOURCES/bin/x86_64/ffmpeg" "$RESOURCES/bin/x86_64/ffprobe"
xattr -dr com.apple.quarantine "$RESOURCES/bin" 2>/dev/null || true

SOURCES=("$ROOT"/Sources/OpenPull/*.swift)
ARM_BINARY="$BUILD/$EXECUTABLE_NAME-arm64"
X64_BINARY="$BUILD/$EXECUTABLE_NAME-x86_64"

compile_slice() {
  local target="$1"
  local output="$2"
  echo "Kompiluji $APP_NAME pro $target…"
  xcrun --sdk macosx swiftc \
    -swift-version 5 \
    -parse-as-library \
    -O \
    -sdk "$SDK" \
    -target "$target" \
    "${SOURCES[@]}" \
    -framework SwiftUI \
    -framework AppKit \
    -framework Foundation \
    -o "$output"
}

compile_slice "$TARGET_ARM64" "$ARM_BINARY"
compile_slice "$TARGET_X64" "$X64_BINARY"

echo "Spojuji Universal 2 executable (arm64 + x86_64)…"
xcrun lipo -create "$ARM_BINARY" "$X64_BINARY" -output "$MACOS/$EXECUTABLE_NAME"
rm -f "$ARM_BINARY" "$X64_BINARY"
chmod +x "$MACOS/$EXECUTABLE_NAME"

ARCHS="$(xcrun lipo -archs "$MACOS/$EXECUTABLE_NAME")"
if [[ "$ARCHS" != *"arm64"* || "$ARCHS" != *"x86_64"* ]]; then
  echo "Chyba: výsledný executable není Universal 2 ($ARCHS)."
  exit 1
fi

# Bez placeného Apple Developer účtu používáme ad-hoc podpis.
# Na jiném Macu proto může Gatekeeper při prvním spuštění vyžadovat ruční povolení.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

# Přenos přes ZIP je spolehlivější než kopírování obsahu .app po jednotlivých
# souborech. Výsledný ZIP už obsahuje yt-dlp, FFmpeg i FFprobe.
PORTABLE_ZIP="$BUILD/$APP_NAME-$VERSION-standalone-universal.zip"
rm -f "$PORTABLE_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PORTABLE_ZIP"

echo
echo "Hotovo: $APP"
echo "Architektury aplikace: $ARCHS"
echo "Standalone balíček: $PORTABLE_ZIP"
echo "Spuštění: open \"$APP\""
