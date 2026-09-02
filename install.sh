#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/config.sh"
"$ROOT/build.sh"
APP="$ROOT/build/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"
rm -rf "$DEST"
ditto "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
echo "Nainstalováno: $DEST"
open "$DEST"
