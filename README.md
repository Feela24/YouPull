# YoutubePull

A native macOS downloader GUI powered by **yt-dlp** and **FFmpeg**.

YoutubePull is designed as a simple macOS app for downloading video or audio from sites supported by yt-dlp, with a native SwiftUI interface, download queue, playlist handling, embedded cover artwork, download estimates, history, and Czech/English localization.

> **Note:** Download only content you are allowed to download. YoutubePull does not bypass DRM.

## Features

- Native **SwiftUI** macOS interface
- Video and audio downloads
- **M4A / MP3** audio output
- **MP4 / WebM** video output
- Selectable video quality
- Download queue
- One set of download settings for the whole queue
- Start the queue manually after adding items
- Stop an active download without clearing the queue
- Remove queued items and start the remaining queue again
- Playlist detection
  - add only the current video
  - or add/download the whole playlist
- Estimated download size for the selected format when available
- Embedded thumbnail / cover artwork
- Optional subtitles
- Download history
- Open the current download folder in Finder
- YouTube browser-cookie support for cases where YouTube requires authentication
- Czech and English interface
- Standalone build with bundled:
  - `yt-dlp`
  - `ffmpeg`
  - `ffprobe`
- **Universal 2** build:
  - Apple Silicon (`arm64`)
  - Intel (`x86_64`)
- macOS 13 Ventura or newer

## Screenshot

Add your screenshot to the repository, for example:

```text
docs/youtubepull.png
```

Then uncomment this line:

<!-- ![YoutubePull](docs/youtubepull.png) -->

## Requirements for building

- macOS 13+
- Xcode Command Line Tools
- Internet connection during the first standalone build

Install the command line tools if necessary:

```bash
xcode-select --install
```

## Build

Clone the repository:

```bash
git clone https://github.com/TheFilipGames/YoutubePull.git
cd YoutubePull
```

Build the app:

```bash
./build.sh
```

The first standalone build downloads the required yt-dlp and FFmpeg binaries and bundles them inside the application.

The output is created in:

```text
build/YoutubePull.app
```

A distributable standalone archive is also created:

```text
build/YoutubePull-1.5.1-standalone-universal.zip
```

## Install

You can copy the built app manually:

```bash
cp -R build/YoutubePull.app /Applications/
```

or use:

```bash
./install.sh
```

Then launch:

```bash
open /Applications/YoutubePull.app
```

## Standalone build

The built application contains its own downloader tools, so the target Mac does **not** need:

- Homebrew
- Python
- yt-dlp installed system-wide
- FFmpeg installed system-wide
- Xcode

The app bundle contains the required runtime binaries.

## Universal 2

YoutubePull is built for both:

```text
arm64
x86_64
```

On Apple Silicon Macs, macOS runs the native ARM version.  
On Intel Macs, macOS runs the native Intel version.

The two architectures are stored in the same application bundle; they do **not** run at the same time.

You can verify the standalone build with:

```bash
./scripts/verify-standalone.sh
```

## Custom app icon

Prepare a square PNG, ideally `1024x1024`, then run:

```bash
./scripts/make-icon.sh ~/Downloads/YoutubePull-icon.png
```

This creates:

```text
Resources/AppIcon.icns
```

Rebuild the app afterward:

```bash
./build.sh
```

## YouTube cookies

YouTube may occasionally require sign-in, anti-bot verification, or return HTTP 429 errors.

YoutubePull can let yt-dlp read cookies from a supported browser profile. Choose your browser in the app settings, for example:

- Firefox
- Chrome
- Safari

You should already be signed in to YouTube in that browser.

YoutubePull does not copy browser cookies into its download history.

## Playlists

When a YouTube video URL contains playlist context, such as:

```text
https://www.youtube.com/watch?v=VIDEO_ID&list=PLAYLIST_ID
```

YoutubePull asks whether you want to use:

- only the current video
- the whole playlist

A direct playlist URL is treated as a playlist automatically.

## Download queue

Adding a URL does not immediately start downloading.

Typical workflow:

1. Paste a URL.
2. Load video information.
3. Add the video or playlist to the queue.
4. Add more items if needed.
5. Select the output settings for the whole queue.
6. Press **Download Queue**.
7. If necessary, press **Stop Download**.
8. Remove unwanted queued items and start the queue again.

Completed items remain completed. Waiting items remain in the queue.

## Embedded thumbnails

For supported output formats, YoutubePull uses yt-dlp/FFmpeg to embed the thumbnail directly into the resulting media file as cover artwork.

For example, an M4A file can appear in music players with the YouTube thumbnail as its artwork instead of creating a separate JPG next to it.

## Estimated file size

When yt-dlp exposes enough format metadata, YoutubePull shows an estimated file size for the selected output.

The value is only an estimate. The final size can differ when:

- FFmpeg has to transcode the media
- the server does not expose an exact content length
- variable bitrate is used
- metadata, subtitles, or artwork are added

## Language

YoutubePull currently supports:

- 🇨🇿 Čeština
- 🇬🇧 English

The language can be changed from the macOS application menu:

```text
YoutubePull → Settings…
```

## Gatekeeper and signing

YoutubePull can be built and used without a paid Apple Developer account.

The local build uses ad-hoc code signing. Because it is not notarized by Apple, macOS may warn when the app is copied to another Mac.

If macOS blocks the app, use:

```text
System Settings → Privacy & Security → Open Anyway
```

For personal use, this does not require a paid Apple Developer account.

Public distribution without Gatekeeper warnings would require Apple Developer ID signing and notarization.

## Project structure

```text
YoutubePull/
├── Sources/
│   └── OpenPull/
│       ├── AppModel.swift
│       ├── ContentView.swift
│       ├── Models.swift
│       ├── YTDLPService.swift
│       └── ...
├── Resources/
│   └── AppIcon.icns
├── scripts/
│   ├── make-icon.sh
│   └── verify-standalone.sh
├── build.sh
├── install.sh
├── config.sh
└── README.md
```

> The source directory may still contain the original internal `OpenPull` module name. The distributed application name is **YoutubePull**.

## Technology

- Swift
- SwiftUI
- AppKit where macOS-specific behavior is required
- yt-dlp
- FFmpeg / ffprobe

## Updating yt-dlp / FFmpeg

Runtime dependencies are bundled into the standalone app during the build process.

To refresh bundled binaries, rebuild using the project's standalone build scripts. If you keep downloaded dependency caches locally, remove or refresh them according to the build script before rebuilding.

## Privacy

YoutubePull is a local desktop application.

Downloads and history are handled on your Mac. Browser authentication, when enabled, is passed to yt-dlp through its browser-cookie integration.

YoutubePull does not require a YoutubePull account or a custom backend server.

## License

Choose a license before publishing the repository.

For an open-source project, a common choice is the **MIT License**. If you choose MIT, add a `LICENSE` file to the root of the repository.

Also review the licenses of bundled third-party components, especially yt-dlp and FFmpeg, before distributing binary releases.

## Credits

YoutubePull is built on top of:

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [FFmpeg](https://ffmpeg.org/)

Without these projects, YoutubePull would not exist.
