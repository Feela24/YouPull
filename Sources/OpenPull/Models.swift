import Foundation

enum MediaMode: String, CaseIterable, Identifiable, Codable {
    case video
    case audio
    var id: String { rawValue }

    func displayName(_ language: AppLanguage) -> String {
        L10n.text(rawValue, language: language)
    }
}

enum VideoContainer: String, CaseIterable, Identifiable, Codable {
    case mp4 = "MP4"
    case webm = "WebM"
    var id: String { rawValue }
    var ytDLPValue: String { rawValue.lowercased() }
}

enum AudioFormat: String, CaseIterable, Identifiable, Codable {
    case mp3 = "MP3"
    case m4a = "M4A"
    var id: String { rawValue }
    var ytDLPValue: String { rawValue.lowercased() }
}

enum DownloadScope: String, Codable, Equatable {
    case singleVideo
    case playlist

    func displayName(_ language: AppLanguage) -> String {
        switch self {
        case .singleVideo: return L10n.text("scope.single", language: language)
        case .playlist: return L10n.text("scope.playlist", language: language)
        }
    }
}

enum CookieBrowser: String, CaseIterable, Identifiable, Codable {
    case none
    case chrome
    case firefox
    case safari
    case brave
    case edge
    case chromium
    case opera
    case vivaldi
    case whale

    var id: String { rawValue }

    func displayName(_ language: AppLanguage) -> String {
        switch self {
        case .none: return L10n.text("youtubeCookies.none", language: language)
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .firefox: return "Firefox"
        case .brave: return "Brave"
        case .edge: return "Microsoft Edge"
        case .chromium: return "Chromium"
        case .opera: return "Opera"
        case .vivaldi: return "Vivaldi"
        case .whale: return "Whale"
        }
    }

    var ytDLPValue: String? {
        self == .none ? nil : rawValue
    }
}

struct MediaFormatInfo: Equatable {
    let formatID: String
    let fileExtension: String?
    let fileSize: Int64?
    let approximateFileSize: Int64?
    let totalBitrateKbps: Double?
    let audioBitrateKbps: Double?
    let height: Int?
    let hasVideo: Bool
    let hasAudio: Bool
}

struct MediaInfo: Equatable {
    let id: String
    let title: String
    let thumbnailURL: URL?
    let duration: Double?
    let availableHeights: [Int]
    let formats: [MediaFormatInfo]
    let playlistID: String?
    let playlistTitle: String?

    var durationText: String? {
        guard let duration else { return nil }
        let total = Int(duration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var hasPlaylistContext: Bool {
        guard let playlistID else { return false }
        return !playlistID.isEmpty
    }

    /// Přibližný počet bajtů pro právě zvolený výstup. Jde o odhad podle
    /// velikostí/bitratů streamů, které yt-dlp zveřejní v metadatech. Po
    /// převodu přes ffmpeg se může výsledná velikost mírně lišit.
    func estimatedBytes(mediaMode: MediaMode,
                        videoContainer: VideoContainer,
                        audioFormat: AudioFormat,
                        maxHeight: Int?) -> Int64? {
        switch mediaMode {
        case .audio:
            guard let source = bestAudioFormat() else { return nil }

            // U MP3 s kvalitou 0 jde typicky o VBR výstup. Zdrojová velikost
            // by proto byla zavádějící; použijeme konzervativní V0 odhad.
            if audioFormat == .mp3, let duration, duration > 0 {
                let estimatedBitrate = 245_000.0 // bit/s, přibližně LAME V0
                return Int64((duration * estimatedBitrate / 8.0).rounded())
            }

            return estimatedBytes(of: source)

        case .video:
            guard let video = bestVideoFormat(container: videoContainer, maxHeight: maxHeight) else {
                return nil
            }

            var total = estimatedBytes(of: video)
            if video.hasAudio { return total }

            if let audio = bestAudioFormat(preferredExtension: videoContainer == .mp4 ? "m4a" : "webm"),
               let audioBytes = estimatedBytes(of: audio) {
                if let total { return total + audioBytes }
                total = audioBytes
            }
            return total
        }
    }

    private func bestAudioFormat(preferredExtension: String? = nil) -> MediaFormatInfo? {
        let audioOnly = formats.filter { $0.hasAudio && !$0.hasVideo }
        var candidates = audioOnly.isEmpty ? formats.filter(\.hasAudio) : audioOnly
        guard !candidates.isEmpty else { return nil }

        if let preferredExtension {
            let preferred = candidates.filter { $0.fileExtension?.lowercased() == preferredExtension }
            if !preferred.isEmpty { candidates = preferred }
        }

        return candidates.max { lhs, rhs in
            audioScore(lhs) < audioScore(rhs)
        }
    }

    private func bestVideoFormat(container: VideoContainer, maxHeight: Int?) -> MediaFormatInfo? {
        var candidates = formats.filter { format in
            guard format.hasVideo else { return false }
            if let maxHeight, let height = format.height, height > maxHeight { return false }
            return true
        }
        guard !candidates.isEmpty else { return nil }

        let desiredExtension = container.ytDLPValue
        let preferred = candidates.filter { $0.fileExtension?.lowercased() == desiredExtension }
        if !preferred.isEmpty { candidates = preferred }

        return candidates.max { lhs, rhs in
            let lhsHeight = lhs.height ?? 0
            let rhsHeight = rhs.height ?? 0
            if lhsHeight != rhsHeight { return lhsHeight < rhsHeight }
            return videoScore(lhs) < videoScore(rhs)
        }
    }

    private func audioScore(_ format: MediaFormatInfo) -> Double {
        format.audioBitrateKbps ?? format.totalBitrateKbps ?? 0
    }

    private func videoScore(_ format: MediaFormatInfo) -> Double {
        format.totalBitrateKbps ?? 0
    }

    private func estimatedBytes(of format: MediaFormatInfo) -> Int64? {
        if let size = format.fileSize, size > 0 { return size }
        if let size = format.approximateFileSize, size > 0 { return size }

        guard let duration, duration > 0 else { return nil }
        let bitrate = format.totalBitrateKbps ?? format.audioBitrateKbps
        guard let bitrate, bitrate > 0 else { return nil }
        return Int64((duration * bitrate * 1000.0 / 8.0).rounded())
    }
}

struct QueueSettings {
    let outputDirectory: URL
    let mediaMode: MediaMode
    let videoContainer: VideoContainer
    let audioFormat: AudioFormat
    let maxHeight: Int?
    let writeSubtitles: Bool
    let writeAutoSubtitles: Bool
    let embedSubtitles: Bool
    let subtitleLanguages: String
    let embedThumbnail: Bool
    let cookieBrowser: CookieBrowser
    let language: AppLanguage
}

struct DownloadOptions {
    let url: String
    let title: String
    let outputDirectory: URL
    let mediaMode: MediaMode
    let videoContainer: VideoContainer
    let audioFormat: AudioFormat
    let maxHeight: Int?
    let scope: DownloadScope
    let writeSubtitles: Bool
    let writeAutoSubtitles: Bool
    let embedSubtitles: Bool
    let subtitleLanguages: String
    let embedThumbnail: Bool
    let cookieBrowser: CookieBrowser
    let language: AppLanguage
}

enum DownloadState: Equatable {
    case queued
    case downloading
    case processing
    case completed
    case failed(String)

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .queued: return L10n.text("state.queued", language: language)
        case .downloading: return L10n.text("state.downloading", language: language)
        case .processing: return L10n.text("state.processing", language: language)
        case .completed: return L10n.text("state.completed", language: language)
        case .failed: return L10n.text("state.failed", language: language)
        }
    }
}

struct DownloadJob: Identifiable {
    let id: UUID
    let sourceURL: String
    let sourceTitle: String
    let scope: DownloadScope
    let mediaInfo: MediaInfo?
    var state: DownloadState
    var progress: Double
    var speed: String
    var eta: String
    var currentTitle: String
    var outputFiles: [String]

    init(url: String, title: String, scope: DownloadScope = .singleVideo, mediaInfo: MediaInfo? = nil) {
        self.id = UUID()
        self.sourceURL = url
        self.sourceTitle = title
        self.scope = scope
        self.mediaInfo = mediaInfo
        self.state = .queued
        self.progress = 0
        self.speed = ""
        self.eta = ""
        self.currentTitle = title
        self.outputFiles = []
    }
}

struct HistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let sourceURL: String
    let filePath: String
    let completedAt: Date
    let mode: MediaMode
    let format: String
}

enum DownloadEvent {
    case progress(percent: Double, speed: String, eta: String, title: String)
    case processing
    case outputFile(String)
}
