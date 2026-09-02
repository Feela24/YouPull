#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-$ROOT/Resources/AppIcon-1024.png}"
ICONSET="$ROOT/build/AppIcon.iconset"
OUTPUT="$ROOT/Resources/AppIcon.icns"

if [[ ! -f "$SOURCE" ]]; then
  echo "Chybí zdrojová 1024×1024 PNG ikona: $SOURCE"
  echo "Použití: ./scripts/make-icon.sh /cesta/k/ikone-1024.png"
  exit 1
fi

mkdir -p "$ROOT/build"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

make_png() {
  local size="$1"
  local name="$2"
  sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/$name" >/dev/null
}

make_png 16   icon_16x16.png
make_png 32   icon_16x16@2x.png
make_png 32   icon_32x32.png
make_png 64   icon_32x32@2x.png
make_png 128  icon_128x128.png
make_png 256  icon_128x128@2x.png
make_png 256  icon_256x256.png
make_png 512  icon_256x256@2x.png
make_png 512  icon_512x512.png
make_png 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$ICONSET"
echo "Hotovo: $OUTPUT"
