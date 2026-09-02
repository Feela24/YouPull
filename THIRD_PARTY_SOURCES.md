# Third-party source and license information

YouPull uses third-party helper executables. This document is intended to
make the provenance of those components clear for people who build or
redistribute the standalone app.

## yt-dlp

Project: https://github.com/yt-dlp/yt-dlp

The standalone build downloads the official `yt-dlp_macos` release executable.
yt-dlp documents that PyInstaller-bundled executables contain GPLv3+ licensed
code and are distributed under GPLv3+ terms as a combined executable.

The build also downloads:
- `LICENSE`
- `THIRD_PARTY_LICENSES.txt`

When publishing a binary YouPull release, keep those files in the app
bundle. For strict redistribution compliance, also ensure the corresponding
source for the exact yt-dlp release and its GPL-covered bundled components
remains available to recipients.

## FFmpeg / ffprobe

Binary distributor: https://github.com/eugeneware/ffmpeg-static  
FFmpeg: https://ffmpeg.org/

The current build script uses ffmpeg-static release `b6.1.1` for:
- macOS arm64
- macOS x86_64

The build downloads each binary asset's accompanying `.LICENSE` and `.README`
files. Those README files identify build details and upstream sources.

ffmpeg-static itself is licensed GPL-3.0-or-later. The exact FFmpeg binary
license depends on its compile configuration and statically linked libraries;
preserve the license/build metadata shipped with the selected binary assets.

## YouPull source code

The Swift source code authored for YouPull is released under the MIT
License in the repository root. Third-party components retain their own
licenses.

## Redistribution checklist

Before publishing a standalone ZIP:

1. Build with `./build.sh`.
2. Verify that `YouPull.app/Contents/Resources/THIRD_PARTY_NOTICES.txt`
   exists.
3. Verify that `YouPull.app/Contents/Resources/licenses/` contains the
   yt-dlp and ffmpeg-static license files.
4. Keep those files inside the distributed ZIP.
5. Make the corresponding source for GPL-covered components available as
   required by their licenses.
6. Do not imply that YouPull is an official YouTube/Google product.

This file is practical project documentation, not legal advice.
