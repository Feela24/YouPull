#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config.sh"
APP="$ROOT/build/$APP_NAME.app"

if [[ ! -d "$APP" ]]; then
  echo "Nejdřív spusť ./build.sh"
  exit 1
fi

EXEC="$APP/Contents/MacOS/$EXECUTABLE_NAME"
BIN="$APP/Contents/Resources/bin"

check_exec() {
  [[ -x "$1" ]] || { echo "Chybí executable: $1"; exit 1; }
}

check_exec "$EXEC"
check_exec "$BIN/yt-dlp"
check_exec "$BIN/arm64/ffmpeg"
check_exec "$BIN/arm64/ffprobe"
check_exec "$BIN/x86_64/ffmpeg"
check_exec "$BIN/x86_64/ffprobe"

APP_ARCHS="$(lipo -archs "$EXEC")"
YTDLP_ARCHS="$(lipo -archs "$BIN/yt-dlp")"

[[ "$APP_ARCHS" == *"arm64"* && "$APP_ARCHS" == *"x86_64"* ]] || {
  echo "Aplikace není Universal 2: $APP_ARCHS"; exit 1;
}
[[ "$YTDLP_ARCHS" == *"arm64"* && "$YTDLP_ARCHS" == *"x86_64"* ]] || {
  echo "yt-dlp není Universal 2: $YTDLP_ARCHS"; exit 1;
}
[[ "$(lipo -archs "$BIN/arm64/ffmpeg")" == *"arm64"* ]] || exit 1
[[ "$(lipo -archs "$BIN/x86_64/ffmpeg")" == *"x86_64"* ]] || exit 1

codesign --verify --deep --strict "$APP"

echo "OK: OpenPull je standalone Universal 2."
echo "Aplikace: $APP_ARCHS"
echo "yt-dlp:    $YTDLP_ARCHS"
echo "FFmpeg:    nativní arm64 + nativní x86_64"
echo "Runtime Homebrew/Python: není potřeba"
