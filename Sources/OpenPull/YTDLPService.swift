import Foundation

private struct YTDLPInfo: Decodable {
    struct Format: Decodable {
        let formatID: String?
        let fileExtension: String?
        let fileSize: Double?
        let approximateFileSize: Double?
        let totalBitrate: Double?
        let audioBitrate: Double?
        let height: Double?
        let vcodec: String?
        let acodec: String?

        enum CodingKeys: String, CodingKey {
            case formatID = "format_id"
            case fileExtension = "ext"
            case fileSize = "filesize"
            case approximateFileSize = "filesize_approx"
            case totalBitrate = "tbr"
            case audioBitrate = "abr"
            case height
            case vcodec
            case acodec
        }
    }

    let id: String?
    let title: String?
    let thumbnail: String?
    let duration: Double?
    let formats: [Format]?
    let playlistID: String?
    let playlistTitle: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case thumbnail
        case duration
        case formats
        case playlistID = "playlist_id"
        case playlistTitle = "playlist_title"
    }
}

enum YTDLPServiceError: LocalizedError {
    case missingYTDLP(AppLanguage)
    case missingFFmpeg(AppLanguage)
    case invalidMetadata(AppLanguage)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingYTDLP(let language):
            return L10n.text("error.missingYTDLP", language: language)
        case .missingFFmpeg(let language):
            return L10n.text("error.missingFFmpeg", language: language)
        case .invalidMetadata(let language):
            return L10n.text("error.invalidMetadata", language: language)
        case .downloadFailed(let message):
            return message
        }
    }
}

struct YTDLPService {
    func analyze(url: String,
                 cookieBrowser: CookieBrowser = .none,
                 language: AppLanguage = .cs) async throws -> MediaInfo {
        guard let tools = ToolLocator.locate() else { throw YTDLPServiceError.missingYTDLP(language) }

        var arguments = ["--no-warnings", "--no-playlist", "--dump-single-json"]
        arguments += authenticationArguments(cookieBrowser)
        arguments += youtubeCompatibilityArguments(url: url, browser: cookieBrowser)
        arguments.append(url)

        let result = try await ProcessRunner.run(
            executable: tools.ytDLP,
            arguments: arguments
        )

        guard result.exitCode == 0 else {
            throw YTDLPServiceError.downloadFailed(
                friendlyError(result.stderr, browser: cookieBrowser, language: language)
            )
        }

        guard let data = result.stdout.data(using: .utf8),
              let info = try? JSONDecoder().decode(YTDLPInfo.self, from: data) else {
            throw YTDLPServiceError.invalidMetadata(language)
        }

        let parsedFormats = (info.formats ?? []).map { format in
            MediaFormatInfo(
                formatID: format.formatID ?? "",
                fileExtension: format.fileExtension,
                fileSize: format.fileSize.flatMap { $0 > 0 ? Int64($0.rounded()) : nil },
                approximateFileSize: format.approximateFileSize.flatMap { $0 > 0 ? Int64($0.rounded()) : nil },
                totalBitrateKbps: format.totalBitrate,
                audioBitrateKbps: format.audioBitrate,
                height: format.height.flatMap { $0 > 0 ? Int($0.rounded()) : nil },
                hasVideo: (format.vcodec ?? "none") != "none",
                hasAudio: (format.acodec ?? "none") != "none"
            )
        }

        let heights = Set(parsedFormats.compactMap { format -> Int? in
            guard format.hasVideo else { return nil }
            return format.height
        }).sorted(by: >)

        return MediaInfo(
            id: info.id ?? UUID().uuidString,
            title: info.title ?? url,
            thumbnailURL: info.thumbnail.flatMap(URL.init(string:)),
            duration: info.duration,
            availableHeights: heights,
            formats: parsedFormats,
            playlistID: info.playlistID,
            playlistTitle: info.playlistTitle
        )
    }

    func download(options: DownloadOptions,
                  onEvent: @escaping (DownloadEvent) -> Void) async throws -> [String] {
        guard let tools = ToolLocator.locate() else { throw YTDLPServiceError.missingYTDLP(options.language) }
        if tools.ffmpeg == nil || tools.ffprobe == nil {
            throw YTDLPServiceError.missingFFmpeg(options.language)
        }

        let arguments = buildArguments(options: options, ffmpeg: tools.ffmpeg)
        let files = LockedStringList()
        let errorLines = LockedStringList()

        let exitCode = try await ProcessRunner.runStreaming(
            executable: tools.ytDLP,
            arguments: arguments
        ) { line in
            if line.hasPrefix("OP_PROGRESS|") {
                if let event = parseProgress(line) { onEvent(event) }
            } else if line.hasPrefix("OP_FILE|") {
                let path = String(line.dropFirst("OP_FILE|".count))
                files.append(path)
                onEvent(.outputFile(path))
            } else if line.localizedCaseInsensitiveContains("post-process") ||
                        line.localizedCaseInsensitiveContains("merg") ||
                        line.localizedCaseInsensitiveContains("ffmpeg") ||
                        line.localizedCaseInsensitiveContains("thumbnail") {
                onEvent(.processing)
            } else if line.localizedCaseInsensitiveContains("error") ||
                        line.localizedCaseInsensitiveContains("warning") {
                errorLines.append(line)
            }
        }

        if exitCode != 0 {
            let raw = errorLines.joined()
            let message = friendlyError(raw, browser: options.cookieBrowser, language: options.language)
            throw YTDLPServiceError.downloadFailed(
                message.isEmpty ? L10n.text("error.downloadFailed", language: options.language) : message
            )
        }

        return files.snapshot()
    }

    private func buildArguments(options: DownloadOptions, ffmpeg: URL?) -> [String] {
        var args: [String] = [
            "--newline",
            "--progress",
            "--progress-template",
            "download:OP_PROGRESS|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(info.title)s",
            "--print",
            "after_move:OP_FILE|%(filepath)s",
            "--paths", options.outputDirectory.path,
            "--no-overwrites"
        ]

        args += authenticationArguments(options.cookieBrowser)
        args += youtubeCompatibilityArguments(url: options.url, browser: options.cookieBrowser)

        if let ffmpeg {
            args += ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path]
        }

        if options.scope == .playlist {
            args += ["--yes-playlist", "-o", "%(playlist_title,channel|Playlist)s/%(playlist_index)03d - %(title)s.%(ext)s"]
        } else {
            args += ["--no-playlist", "-o", "%(title)s.%(ext)s"]
        }

        // --embed-thumbnail použije náhled jen jako dočasný soubor a vloží jej
        // do výsledného média. Nezůstává tedy samostatný JPG vedle M4A/MP4.
        // WebM není postprocesorem yt-dlp pro cover art podporován.
        if options.embedThumbnail {
            switch (options.mediaMode, options.videoContainer) {
            case (.audio, _), (.video, .mp4):
                args.append("--embed-thumbnail")
                args.append("--embed-metadata")
            case (.video, .webm):
                break
            }
        }

        if options.writeSubtitles {
            args.append("--write-subs")
            let languages = options.subtitleLanguages.trimmingCharacters(in: .whitespacesAndNewlines)
            args += ["--sub-langs", languages.isEmpty ? "all" : languages]
            if options.writeAutoSubtitles { args.append("--write-auto-subs") }
            if options.embedSubtitles && options.mediaMode == .video { args.append("--embed-subs") }
        }

        switch options.mediaMode {
        case .audio:
            args += [
                "-f", "ba/b",
                "--extract-audio",
                "--audio-format", options.audioFormat.ytDLPValue,
                "--audio-quality", "0"
            ]
        case .video:
            let heightConstraint = options.maxHeight.map { "[height<=\($0)]" } ?? ""
            switch options.videoContainer {
            case .mp4:
                let selector = "bv*\(heightConstraint)[ext=mp4]+ba[ext=m4a]/b\(heightConstraint)[ext=mp4]/bv*\(heightConstraint)+ba/b\(heightConstraint)"
                args += ["-f", selector, "--merge-output-format", "mp4", "--recode-video", "mp4"]
            case .webm:
                let selector = "bv*\(heightConstraint)[ext=webm]+ba[ext=webm]/b\(heightConstraint)[ext=webm]/bv*\(heightConstraint)+ba/b\(heightConstraint)"
                args += ["-f", selector, "--merge-output-format", "webm", "--recode-video", "webm"]
            }
        }

        args.append(options.url)
        return args
    }

    private func authenticationArguments(_ browser: CookieBrowser) -> [String] {
        guard let browserName = browser.ytDLPValue else { return [] }
        return ["--cookies-from-browser", browserName]
    }

    /// YouTube changed the logged-in playback path in August 2026. With browser
    /// cookies, yt-dlp may otherwise select the `tv_downgraded` player client,
    /// which currently returns "The page needs to be reloaded" for some users.
    /// The yt-dlp maintainers recommend explicitly adding default + web_embedded
    /// while this upstream issue is active. Keep this scoped to YouTube and to
    /// authenticated requests so other extractors are unaffected.
    private func youtubeCompatibilityArguments(url: String, browser: CookieBrowser) -> [String] {
        guard browser != .none, isYouTubeURL(url) else { return [] }
        return [
            "--extractor-args",
            "youtube:player_client=default,web_embedded"
        ]
    }

    private func isYouTubeURL(_ value: String) -> Bool {
        guard let host = URL(string: value)?.host?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    private func parseProgress(_ line: String) -> DownloadEvent? {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else { return nil }
        let percentString = parts[1]
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        let percent = Double(percentString) ?? 0
        let title = parts.dropFirst(4).joined(separator: "|")
        return .progress(percent: min(max(percent / 100.0, 0), 1),
                         speed: parts[2].trimmingCharacters(in: .whitespaces),
                         eta: parts[3].trimmingCharacters(in: .whitespaces),
                         title: title)
    }

    private func friendlyError(_ rawValue: String,
                               browser: CookieBrowser,
                               language: AppLanguage) -> String {
        let cleaned = cleanError(rawValue)
        let lower = rawValue.lowercased()
        let youtubeBlocked = lower.contains("429") ||
            lower.contains("too many requests") ||
            lower.contains("confirm you’re not a bot") ||
            lower.contains("confirm you're not a bot") ||
            lower.contains("login_required") ||
            lower.contains("the page needs to be reloaded")

        guard youtubeBlocked else {
            return cleaned.isEmpty ? L10n.text("error.downloadFailed", language: language) : cleaned
        }

        let guidance: String
        if browser == .none {
            guidance = L10n.text("error.youtubeBlocked.none", language: language)
        } else {
            guidance = L10n.format(
                "error.youtubeBlocked.browser",
                language: language,
                browser.displayName(language)
            )
        }

        return cleaned.isEmpty ? guidance : "\(guidance)\n\n\(cleaned)"
    }

    private func cleanError(_ value: String) -> String {
        let lines = value.split(separator: "\n").map(String.init)
        return lines.suffix(8).joined(separator: "\n")
    }
}

final class LockedStringList {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value)
        if values.count > 12 { values.removeFirst(values.count - 12) }
    }

    func joined() -> String {
        lock.lock()
        defer { lock.unlock() }
        return values.joined(separator: "\n")
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
