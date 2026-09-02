import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var urlText: String = ""
    @Published var mediaInfo: MediaInfo?
    @Published var isAnalyzing = false
    @Published var analysisError: String?

    // Globální nastavení celé fronty. Do jednotlivých položek se nekopíruje
    // při přidání; snapshot se vytvoří až po kliknutí na „Stáhnout frontu“.
    @Published var mediaMode: MediaMode = .video
    @Published var videoContainer: VideoContainer = .mp4
    @Published var audioFormat: AudioFormat = .m4a
    @Published var selectedHeight: Int?
    @Published var writeSubtitles = false
    @Published var writeAutoSubtitles = true
    @Published var embedSubtitles = false
    @Published var subtitleLanguages = "cs,en"
    @Published var embedThumbnail = true
    @Published var cookieBrowser: CookieBrowser = .none

    @Published var language: AppLanguage
    @Published var outputDirectory: URL
    @Published var jobs: [DownloadJob] = []
    @Published var history: [HistoryItem] = []
    @Published var toolStatus: String
    @Published var isQueueRunning = false
    @Published var isQueueStopping = false

    private let service = YTDLPService()
    private let historyStore = HistoryStore()
    private var queueTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var lastAutoClipboardURL = ""
    private var activeDownloadSessions: [UUID: UUID] = [:]

    init() {
        // Nejdřív jazyk spočítáme do lokální proměnné. Během inicializace
        // nesmíme číst @Published vlastnost přes `self`, dokud nejsou
        // inicializované všechny stored properties (Swift 5.10/6 je v tom přísnější).
        let resolvedLanguage: AppLanguage
        if let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage"),
           let parsedLanguage = AppLanguage(rawValue: savedLanguage) {
            resolvedLanguage = parsedLanguage
        } else {
            resolvedLanguage = .cs
        }
        language = resolvedLanguage

        let saved = UserDefaults.standard.string(forKey: "outputDirectory")
        if let saved, FileManager.default.fileExists(atPath: saved) {
            outputDirectory = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            outputDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
        }

        if let savedBrowser = UserDefaults.standard.string(forKey: "cookieBrowser"),
           let browser = CookieBrowser(rawValue: savedBrowser) {
            cookieBrowser = browser
        }

        toolStatus = ToolLocator.statusText(language: resolvedLanguage)
        history = historyStore.load()
        importClipboardURL(force: false)

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.toolStatus = ToolLocator.statusText(language: self.language)
                self.importClipboardURL(force: false)
            }
        }
    }

    deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    func t(_ key: String) -> String {
        L10n.text(key, language: language)
    }

    func tf(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }

    func setLanguage(_ newLanguage: AppLanguage) {
        language = newLanguage
        UserDefaults.standard.set(newLanguage.rawValue, forKey: "appLanguage")
        toolStatus = ToolLocator.statusText(language: newLanguage)
    }

    func importClipboardURL(force: Bool = true) {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }

        if force || urlText.isEmpty || urlText == lastAutoClipboardURL {
            urlText = text
            lastAutoClipboardURL = text
            mediaInfo = nil
            analysisError = nil
        }
    }

    func analyze() {
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        isAnalyzing = true
        analysisError = nil
        let analysisLanguage = language
        let browser = cookieBrowser

        Task {
            do {
                let info = try await service.analyze(url: url, cookieBrowser: browser, language: analysisLanguage)
                mediaInfo = info
                isAnalyzing = false
            } catch {
                mediaInfo = nil
                analysisError = error.localizedDescription
                isAnalyzing = false
            }
        }
    }

    func setCookieBrowser(_ browser: CookieBrowser) {
        cookieBrowser = browser
        UserDefaults.standard.set(browser.rawValue, forKey: "cookieBrowser")
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = outputDirectory
        panel.prompt = t("choose")
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
            UserDefaults.standard.set(url.path, forKey: "outputDirectory")
        }
    }

    func addToQueue() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), ["http", "https"].contains(parsed.scheme?.lowercased() ?? "") else {
            analysisError = t("error.invalidURL")
            return
        }

        let scope: DownloadScope
        if isDirectPlaylistURL(trimmed) {
            scope = .playlist
        } else if hasPlaylistContext(url: trimmed, info: mediaInfo) {
            guard let selectedScope = askPlaylistScope(info: mediaInfo) else { return }
            scope = selectedScope
        } else {
            scope = .singleVideo
        }

        let title: String
        if scope == .playlist {
            title = mediaInfo?.playlistTitle ?? mediaInfo?.title ?? trimmed
        } else {
            title = mediaInfo?.title ?? trimmed
        }

        jobs.append(DownloadJob(url: trimmed, title: title, scope: scope, mediaInfo: mediaInfo))

        // Připravíme pole na další odkaz. Nastavení fronty zůstává beze změny.
        urlText = ""
        mediaInfo = nil
        analysisError = nil
        lastAutoClipboardURL = ""
    }

    func estimatedSizeText(for info: MediaInfo) -> String? {
        guard let bytes = info.estimatedBytes(
            mediaMode: mediaMode,
            videoContainer: videoContainer,
            audioFormat: audioFormat,
            maxHeight: selectedHeight
        ) else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func estimatedSizeText(for job: DownloadJob) -> String? {
        guard job.scope == .singleVideo, let info = job.mediaInfo else { return nil }
        return estimatedSizeText(for: info)
    }

    var queueEstimatedSizeText: String? {
        let queued = jobs.filter { $0.state == .queued }
        guard !queued.isEmpty else { return nil }

        var total: Int64 = 0
        var knownCount = 0
        var unknownCount = 0

        for job in queued {
            guard job.scope == .singleVideo, let info = job.mediaInfo,
                  let bytes = info.estimatedBytes(
                    mediaMode: mediaMode,
                    videoContainer: videoContainer,
                    audioFormat: audioFormat,
                    maxHeight: selectedHeight
                  ) else {
                unknownCount += 1
                continue
            }
            total += bytes
            knownCount += 1
        }

        if knownCount == 0 {
            return t("size.queueUnknown")
        }

        let formatted = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        if unknownCount > 0 {
            return tf("size.queueEstimateWithUnknown", formatted, unknownCount)
        }
        return tf("size.queueEstimate", formatted)
    }

    private func hasPlaylistContext(url: String, info: MediaInfo?) -> Bool {
        if info?.hasPlaylistContext == true { return true }
        guard let components = URLComponents(string: url) else { return false }
        return components.queryItems?.contains(where: {
            $0.name.lowercased() == "list" && !($0.value ?? "").isEmpty
        }) == true
    }

    private func isDirectPlaylistURL(_ url: String) -> Bool {
        guard let parsed = URL(string: url) else { return false }
        let path = parsed.path.lowercased()
        return path == "/playlist" || path.hasSuffix("/playlist")
    }

    private func askPlaylistScope(info: MediaInfo?) -> DownloadScope? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = t("playlistPrompt.title")

        if let playlistTitle = info?.playlistTitle, !playlistTitle.isEmpty {
            alert.informativeText = tf("playlistPrompt.messageNamed", playlistTitle)
        } else {
            alert.informativeText = t("playlistPrompt.message")
        }

        alert.addButton(withTitle: t("playlistPrompt.single"))
        alert.addButton(withTitle: t("playlistPrompt.all"))
        alert.addButton(withTitle: t("playlistPrompt.cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .singleVideo
        case .alertSecondButtonReturn: return .playlist
        default: return nil
        }
    }

    func removeJob(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        switch jobs[index].state {
        case .downloading, .processing:
            return
        case .queued, .completed, .failed:
            jobs.remove(at: index)
        }
    }

    func clearCompletedJobs() {
        jobs.removeAll {
            switch $0.state {
            case .completed, .failed: return true
            default: return false
            }
        }
    }

    var queuedCount: Int {
        jobs.filter { $0.state == .queued }.count
    }

    var hasQueuedJobs: Bool { queuedCount > 0 }

    func startDownloads() {
        guard queueTask == nil else { return }

        // Do tohoto běhu zahrneme jen položky, které byly ve frontě v okamžiku
        // kliknutí. Nově přidané položky počkají na další kliknutí.
        let batchIDs = jobs.filter { $0.state == .queued }.map(\.id)
        guard !batchIDs.isEmpty else { return }
        let settings = makeQueueSettingsSnapshot()

        isQueueRunning = true
        isQueueStopping = false
        queueTask = Task { [weak self] in
            guard let self else { return }
            await self.processBatch(ids: batchIDs, settings: settings)
        }
    }

    func stopDownloads() {
        guard let queueTask, isQueueRunning else { return }
        isQueueStopping = true
        queueTask.cancel()
    }

    func clearHistory() {
        history.removeAll()
        historyStore.save(history)
    }

    func revealOutputDirectory() {
        NSWorkspace.shared.open(outputDirectory)
    }

    private func makeQueueSettingsSnapshot() -> QueueSettings {
        QueueSettings(
            outputDirectory: outputDirectory,
            mediaMode: mediaMode,
            videoContainer: videoContainer,
            audioFormat: audioFormat,
            maxHeight: selectedHeight,
            writeSubtitles: writeSubtitles,
            writeAutoSubtitles: writeAutoSubtitles,
            embedSubtitles: embedSubtitles,
            subtitleLanguages: subtitleLanguages,
            embedThumbnail: embedThumbnail,
            cookieBrowser: cookieBrowser,
            language: language
        )
    }

    private func makeOptions(for job: DownloadJob, settings: QueueSettings) -> DownloadOptions {
        DownloadOptions(
            url: job.sourceURL,
            title: job.sourceTitle,
            outputDirectory: settings.outputDirectory,
            mediaMode: settings.mediaMode,
            videoContainer: settings.videoContainer,
            audioFormat: settings.audioFormat,
            maxHeight: settings.maxHeight,
            scope: job.scope,
            writeSubtitles: settings.writeSubtitles,
            writeAutoSubtitles: settings.writeAutoSubtitles,
            embedSubtitles: settings.embedSubtitles,
            subtitleLanguages: settings.subtitleLanguages,
            embedThumbnail: settings.embedThumbnail,
            cookieBrowser: settings.cookieBrowser,
            language: settings.language
        )
    }

    private func processBatch(ids: [UUID], settings: QueueSettings) async {
        defer {
            queueTask = nil
            isQueueRunning = false
            isQueueStopping = false
        }

        for id in ids {
            if Task.isCancelled { break }

            guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .queued else { continue }
            let options = makeOptions(for: jobs[index], settings: settings)
            let sessionID = UUID()
            activeDownloadSessions[id] = sessionID
            jobs[index].state = .downloading

            do {
                let files = try await service.download(options: options) { [weak self] event in
                    Task { @MainActor in
                        self?.handle(event: event, for: id, sessionID: sessionID)
                    }
                }

                try Task.checkCancellation()
                activeDownloadSessions[id] = nil

                if let current = jobs.firstIndex(where: { $0.id == id }) {
                    jobs[current].state = .completed
                    jobs[current].progress = 1
                    if jobs[current].outputFiles.isEmpty { jobs[current].outputFiles = files }
                }
                addHistory(for: options, files: files)
            } catch {
                activeDownloadSessions[id] = nil

                if error is CancellationError || Task.isCancelled {
                    resetJobAfterCancellation(id)
                    break
                }

                if let current = jobs.firstIndex(where: { $0.id == id }) {
                    jobs[current].state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func resetJobAfterCancellation(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = .queued
        jobs[index].progress = 0
        jobs[index].speed = ""
        jobs[index].eta = ""
        jobs[index].currentTitle = jobs[index].sourceTitle
    }

    private func handle(event: DownloadEvent, for id: UUID, sessionID: UUID) {
        guard activeDownloadSessions[id] == sessionID,
              let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        switch event {
        case .progress(let percent, let speed, let eta, let title):
            jobs[index].state = .downloading
            jobs[index].progress = percent
            jobs[index].speed = speed == "NA" ? "" : speed
            jobs[index].eta = eta == "NA" ? "" : eta
            if title != "NA" && !title.isEmpty { jobs[index].currentTitle = title }
        case .processing:
            jobs[index].state = .processing
        case .outputFile(let path):
            if !jobs[index].outputFiles.contains(path) { jobs[index].outputFiles.append(path) }
        }
    }

    private func addHistory(for options: DownloadOptions, files: [String]) {
        for file in files {
            let title = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
            history.insert(
                HistoryItem(
                    id: UUID(),
                    title: title,
                    sourceURL: options.url,
                    filePath: file,
                    completedAt: Date(),
                    mode: options.mediaMode,
                    format: options.mediaMode == .audio ? options.audioFormat.rawValue : options.videoContainer.rawValue
                ),
                at: 0
            )
        }
        if history.count > 500 { history = Array(history.prefix(500)) }
        historyStore.save(history)
    }
}
