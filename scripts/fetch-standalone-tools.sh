#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/Resources/bin"
LICENSES="$ROOT/Resources/licenses"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/openpull-tools.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$BIN/arm64" "$BIN/x86_64" "$LICENSES/yt-dlp" "$LICENSES/ffmpeg-static"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Chybí nástroj '$1'. Je součástí standardního macOS/Xcode Command Line Tools."
    exit 1
  }
}

need curl
need shasum
need lipo
need gzip

fetch() {
  local url="$1"
  local out="$2"
  echo "Stahuji: $(basename "$out")"
  curl --fail --location --retry 3 --retry-delay 1 --silent --show-error \
    "$url" -o "$out"
}

echo "Připravuji standalone nástroje pro OpenPull…"

# -----------------------------------------------------------------------------
# yt-dlp: official Universal macOS standalone binary (arm64 + x86_64)
# -----------------------------------------------------------------------------
YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
YTDLP_SUMS_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS"

fetch "$YTDLP_URL" "$TMP/yt-dlp"
fetch "$YTDLP_SUMS_URL" "$TMP/yt-dlp-SHA2-256SUMS"

expected="$(awk '$2 == "yt-dlp_macos" || $2 == "*yt-dlp_macos" { print $1; exit }' "$TMP/yt-dlp-SHA2-256SUMS")"
actual="$(shasum -a 256 "$TMP/yt-dlp" | awk '{print $1}')"
if [[ -z "$expected" || "$actual" != "$expected" ]]; then
  echo "Chyba: kontrolní součet yt-dlp nesouhlasí."
  exit 1
fi

YTDLP_ARCHS="$(lipo -archs "$TMP/yt-dlp" 2>/dev/null || true)"
if [[ "$YTDLP_ARCHS" != *"arm64"* || "$YTDLP_ARCHS" != *"x86_64"* ]]; then
  echo "Chyba: yt-dlp_macos není Universal 2 (nalezeno: $YTDLP_ARCHS)."
  exit 1
fi

cp "$TMP/yt-dlp" "$BIN/yt-dlp"
chmod +x "$BIN/yt-dlp"

# License text is small and useful when the .app is moved to another Mac.
fetch "https://raw.githubusercontent.com/yt-dlp/yt-dlp/master/LICENSE" "$LICENSES/yt-dlp/LICENSE"
fetch "https://raw.githubusercontent.com/yt-dlp/yt-dlp/master/THIRD_PARTY_LICENSES.txt" "$LICENSES/yt-dlp/THIRD_PARTY_LICENSES.txt"

# -----------------------------------------------------------------------------
# FFmpeg/FFprobe: pinned static macOS binaries for both CPU architectures.
# Pinned version makes builds reproducible. They contain libmp3lame and the
# codecs OpenPull needs for MP3/M4A/MP4/WebM post-processing.
# -----------------------------------------------------------------------------
FFMPEG_TAG="b6.1.1"
FFMPEG_BASE="https://github.com/eugeneware/ffmpeg-static/releases/download/$FFMPEG_TAG"

for pair in "arm64:arm64" "x64:x86_64"; do
  asset_arch="${pair%%:*}"
  dir_arch="${pair##*:}"

  # Use gzip assets to cut the first-build download from ~237 MB to ~85 MB.
  fetch "$FFMPEG_BASE/ffmpeg-darwin-$asset_arch.gz" "$TMP/ffmpeg-$asset_arch.gz"
  fetch "$FFMPEG_BASE/ffprobe-darwin-$asset_arch.gz" "$TMP/ffprobe-$asset_arch.gz"
  gzip -dc "$TMP/ffmpeg-$asset_arch.gz" > "$BIN/$dir_arch/ffmpeg"
  gzip -dc "$TMP/ffprobe-$asset_arch.gz" > "$BIN/$dir_arch/ffprobe"

  fetch "$FFMPEG_BASE/darwin-$asset_arch.LICENSE" "$LICENSES/ffmpeg-static/darwin-$asset_arch.LICENSE"
  fetch "$FFMPEG_BASE/darwin-$asset_arch.README" "$LICENSES/ffmpeg-static/darwin-$asset_arch.README"

  chmod +x "$BIN/$dir_arch/ffmpeg" "$BIN/$dir_arch/ffprobe"
done

# Sanity check the thin helper architectures.
ARM_FFMPEG_ARCHS="$(lipo -archs "$BIN/arm64/ffmpeg" 2>/dev/null || true)"
X64_FFMPEG_ARCHS="$(lipo -archs "$BIN/x86_64/ffmpeg" 2>/dev/null || true)"
if [[ "$ARM_FFMPEG_ARCHS" != *"arm64"* ]]; then
  echo "Chyba: ARM FFmpeg nemá arm64 slice ($ARM_FFMPEG_ARCHS)."
  exit 1
fi
if [[ "$X64_FFMPEG_ARCHS" != *"x86_64"* ]]; then
  echo "Chyba: Intel FFmpeg nemá x86_64 slice ($X64_FFMPEG_ARCHS)."
  exit 1
fi

# Terminal downloads normally have no quarantine, but clear it before signing.
xattr -dr com.apple.quarantine "$BIN" 2>/dev/null || true

echo
printf 'Standalone nástroje jsou připravené.\n'
printf '  yt-dlp:  %s\n' "$(lipo -archs "$BIN/yt-dlp")"
printf '  ffmpeg:  arm64 + x86_64 (separate native helpers)\n'
printf '  ffprobe: arm64 + x86_64 (separate native helpers)\n'
