#!/bin/zsh
set -euo pipefail

echo "OpenPull 1.5 už pro hotovou aplikaci Homebrew nepotřebuje."
echo "Tento skript je jen vývojový fallback pro spuštění helperů mimo standalone bundle."

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew není nainstalované. Pro standalone build spusť jednoduše ./build.sh"
  exit 0
fi

brew install yt-dlp ffmpeg
