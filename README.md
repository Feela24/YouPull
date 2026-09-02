# YouPull

A native macOS downloader GUI powered by **yt-dlp** and **FFmpeg**.

YouPull is a simple macOS app for downloading video or audio from sites
supported by yt-dlp. It provides a native SwiftUI interface, a download queue,
playlist handling, embedded cover artwork, download-size estimates, history,
and Czech/English localization.

> **Note:** Download only content you are allowed to download. YouPull does
> not bypass DRM.

## Features

- Native SwiftUI macOS interface
- Video and audio downloads
- M4A / MP3 audio output
- MP4 / WebM video output
- Selectable video quality
- Download queue with manual start/stop
- Playlist detection
- Estimated download size when metadata is available
- Embedded thumbnail / cover artwork
- Optional subtitles
- Download history
- Browser-cookie support for yt-dlp authentication cases
- Czech and English interface
- Standalone build bundling yt-dlp, ffmpeg and ffprobe
- Universal 2: Apple Silicon (`arm64`) + Intel (`x86_64`)
- macOS 13 Ventura or newer

## Requirements for building

- macOS 13+
- Xcode Command Line Tools
- Internet connection during the first standalone build

Install the command line tools if necessary:

```bash
xcode-select --install
```

## Build

```bash
git clone https://github.com/Feela24/YouPull.git
cd YouPull
./build.sh
```

The first standalone build downloads the required yt-dlp and FFmpeg binaries
and bundles them inside the application.

Output:

```text
build/YouPull.app
build/YouPull-1.5.1-standalone-universal.zip
```

## Install

```bash
cp -R build/YouPull.app /Applications/
open /Applications/YouPull.app
```

Or use:

```bash
./install.sh
```

## Standalone build

The built app contains its own downloader tools, so the target Mac does not
need Homebrew, Python, a system-wide yt-dlp/FFmpeg installation, or Xcode.

## Universal 2

YouPull is built for both `arm64` and `x86_64`. macOS uses the native slice
for the current Mac; both architectures are not executed at the same time.

Verify a standalone build with:

```bash
./scripts/verify-standalone.sh
```

## Custom app icon

```bash
./scripts/make-icon.sh ~/Downloads/YouPull-icon.png
./build.sh
```

This creates/uses `Resources/AppIcon.icns`.

## YouTube cookies

YouTube may occasionally require sign-in, anti-bot verification, or return
HTTP 429 errors. YouPull can let yt-dlp read cookies from a supported
browser profile such as Firefox, Chrome, or Safari.

YouPull does not copy browser cookies into its download history.

## Playlists

When a YouTube video URL contains playlist context, YouPull asks whether to
use only the current video or the whole playlist. A direct playlist URL is
treated as a playlist automatically.

## Download queue

Adding a URL does not immediately start downloading. Add one or more items,
choose output settings for the queue, then press **Download Queue**. An active
download can be stopped without clearing the remaining queue.

## Embedded thumbnails

For supported formats, YouPull uses yt-dlp/FFmpeg to embed the thumbnail
into the resulting media file as cover artwork.

## Estimated file size

When yt-dlp exposes enough format metadata, YouPull shows an estimated file
size. The final size can differ because of transcoding, variable bitrate,
metadata, subtitles, or artwork.

## Language

YouPull currently supports Czech and English. Change the language from:

```text
YouPull → Settings…
```

## Gatekeeper and signing

Local builds use ad-hoc code signing. Because releases are not notarized by
Apple, macOS may warn when the app is copied to another Mac. If macOS blocks
the app, use:

```text
System Settings → Privacy & Security → Open Anyway
```

Public distribution without Gatekeeper warnings requires Apple Developer ID
signing and notarization.

## Technology

- Swift
- SwiftUI
- AppKit
- yt-dlp
- FFmpeg / ffprobe

The source directory may still contain the original internal `OpenPull` module
name. The distributed application name is **YouPull**.

## Privacy

YouPull is a local desktop application. Downloads and history are handled
on the user's Mac. Browser authentication, when enabled, is passed to yt-dlp
through its browser-cookie integration.

YouPull does not require a YouPull account or a custom backend server.

## License

The YouPull Swift source code is licensed under the **MIT License**. See
[`LICENSE`](LICENSE).

The standalone application also bundles third-party executables that are
distributed under their own licenses. In particular, the official
PyInstaller-based yt-dlp macOS executable is documented by yt-dlp as GPLv3+
and the ffmpeg-static distribution used by the build is GPL-3.0-or-later.

See:

- [`Resources/THIRD_PARTY_NOTICES.txt`](Resources/THIRD_PARTY_NOTICES.txt)
- [`THIRD_PARTY_SOURCES.md`](THIRD_PARTY_SOURCES.md)

Those third-party terms are not replaced by the MIT License.

## Trademark notice

YouTube is a trademark of Google LLC. **YouPull is an independent project
and is not affiliated with, endorsed by, or sponsored by YouTube or Google.**

## Credits

YouPull is built on top of:

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [FFmpeg](https://ffmpeg.org/)

Without these projects, YouPull would not exist.
