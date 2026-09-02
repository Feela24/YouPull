import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HSplitView {
            mainPane
                .frame(minWidth: 650)
            historyPane
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
        }
        .frame(minWidth: 1020, minHeight: 720)
    }

    private var mainPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                sourceSection
                if let info = model.mediaInfo { mediaCard(info) }
                queueSettingsSection
                queueSection
            }
            .padding(22)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "OpenPull")
                    .font(.system(size: 28, weight: .bold))
                Text(model.t("app.subtitle"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(
                model.toolStatus,
                systemImage: (ToolLocator.locate()?.ffmpeg != nil && ToolLocator.locate()?.ffprobe != nil)
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var sourceSection: some View {
        GroupBox(model.t("source.title")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField(model.t("source.placeholder"), text: $model.urlText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.analyze() }

                    Button(model.t("source.clipboard")) {
                        model.importClipboardURL()
                    }

                    Button(model.isAnalyzing ? model.t("source.analyzing") : model.t("source.analyze")) {
                        model.analyze()
                    }
                    .disabled(model.isAnalyzing || model.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if model.isAnalyzing {
                    ProgressView().controlSize(.small)
                }

                if let error = model.analysisError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                HStack {
                    Spacer()
                    Button {
                        model.addToQueue()
                    } label: {
                        Label(model.t("source.add"), systemImage: "plus.circle.fill")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func mediaCard(_ info: MediaInfo) -> some View {
        GroupBox(model.t("media.found")) {
            HStack(alignment: .top, spacing: 14) {
                if let url = info.thumbnailURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ZStack { Rectangle().fill(.quaternary); ProgressView() }
                    }
                    .frame(width: 150, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(info.title)
                        .font(.headline)
                        .lineLimit(3)

                    if let duration = info.durationText {
                        Label(duration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if info.hasPlaylistContext {
                        Label(
                            info.playlistTitle.map { model.tf("media.playlistContextNamed", $0) }
                                ?? model.t("media.playlistContext"),
                            systemImage: "list.bullet.rectangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Text(
                        info.availableHeights.isEmpty
                            ? model.t("media.qualityAutomatic")
                            : model.tf("media.availableHeights", info.availableHeights.map { "\($0)p" }.joined(separator: ", "))
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var queueSettingsSection: some View {
        GroupBox(model.t("queueSettings.title")) {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.t("queueSettings.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(model.t("outputType"), selection: $model.mediaMode) {
                    ForEach(MediaMode.allCases) { mode in
                        Text(mode.displayName(model.language)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 16) {
                    if model.mediaMode == .video {
                        Picker(model.t("videoFormat"), selection: $model.videoContainer) {
                            ForEach(VideoContainer.allCases) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .frame(width: 240)

                        Picker(model.t("maxQuality"), selection: $model.selectedHeight) {
                            Text(model.t("best")).tag(Int?.none)
                            ForEach([4320, 2160, 1440, 1080, 720, 480, 360], id: \.self) { height in
                                Text("\(height)p").tag(Int?.some(height))
                            }
                        }
                        .frame(width: 250)
                    } else {
                        Picker(model.t("audioFormat"), selection: $model.audioFormat) {
                            ForEach(AudioFormat.allCases) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .frame(width: 240)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 5) {
                    if let info = model.mediaInfo {
                        if let size = model.estimatedSizeText(for: info) {
                            Label(model.tf("size.currentEstimate", size), systemImage: "internaldrive")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label(model.t("size.unavailable"), systemImage: "internaldrive")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let queueEstimate = model.queueEstimatedSizeText {
                        Label(queueEstimate, systemImage: "tray.full")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if model.mediaInfo != nil || model.queueEstimatedSizeText != nil {
                        Text(model.t("size.help"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Picker(model.t("youtubeCookies"), selection: Binding(
                        get: { model.cookieBrowser },
                        set: { model.setCookieBrowser($0) }
                    )) {
                        ForEach(CookieBrowser.allCases) { browser in
                            Text(browser.displayName(model.language)).tag(browser)
                        }
                    }
                    .frame(width: 290)

                    Text(model.t("youtubeCookies.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(model.t("embedThumbnail"), isOn: $model.embedThumbnail)

                if model.embedThumbnail && model.mediaMode == .video && model.videoContainer == .webm {
                    Label(model.t("embedThumbnail.webmNote"), systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(model.t("subtitles.download"), isOn: $model.writeSubtitles)

                if model.writeSubtitles {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(model.t("subtitles.languages"))
                            TextField(model.t("subtitles.placeholder"), text: $model.subtitleLanguages)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 260)
                        }

                        Toggle(model.t("subtitles.automatic"), isOn: $model.writeAutoSubtitles)
                        if model.mediaMode == .video {
                            Toggle(model.t("subtitles.embed"), isOn: $model.embedSubtitles)
                        }
                    }
                    .padding(.leading, 18)
                }

                Divider()

                HStack {
                    Text(model.t("destination") + ":")
                    Text(model.outputDirectory.path)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(model.t("chooseFolder")) {
                        model.chooseOutputDirectory()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var queueSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(model.t("queue.title"))
                        .font(.headline)

                    if model.queuedCount > 0 {
                        Text(pendingCountText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !model.jobs.isEmpty {
                        Button(model.t("queue.clearFinished")) {
                            model.clearCompletedJobs()
                        }
                        .controlSize(.small)
                    }

                    if model.isQueueRunning {
                        Button(role: .destructive) {
                            model.stopDownloads()
                        } label: {
                            Label(
                                model.isQueueStopping ? model.t("queue.stopping") : model.t("queue.stop"),
                                systemImage: "stop.circle.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isQueueStopping)
                    } else {
                        Button {
                            model.startDownloads()
                        } label: {
                            Label(model.t("queue.download"), systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.hasQueuedJobs)
                    }
                }

                if model.jobs.isEmpty {
                    Text(model.t("queue.empty"))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(model.jobs) { job in
                        queueRow(job)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func queueRow(_ job: DownloadJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.currentTitle)
                    .lineLimit(1)

                Spacer()

                Text(job.state.label(model.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if canRemove(job) {
                    Button {
                        model.removeJob(job.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(model.t("queue.remove"))
                }
            }

            HStack(spacing: 12) {
                Label(job.scope.displayName(model.language), systemImage: job.scope == .playlist ? "list.bullet.rectangle" : "play.rectangle")

                if let size = model.estimatedSizeText(for: job) {
                    Label(model.tf("size.jobEstimate", size), systemImage: "internaldrive")
                } else if job.scope == .playlist {
                    Text(model.t("size.playlistUnknown"))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if job.state != .queued {
                ProgressView(value: job.progress)

                HStack {
                    Text(job.speed)
                        .font(.caption.monospacedDigit())
                    Spacer()
                    if !job.eta.isEmpty {
                        Text(model.tf("eta", job.eta))
                            .font(.caption.monospacedDigit())
                    }
                }
                .foregroundStyle(.secondary)
            }

            if case .failed(let message) = job.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func canRemove(_ job: DownloadJob) -> Bool {
        switch job.state {
        case .downloading, .processing: return false
        case .queued, .completed, .failed: return true
        }
    }

    private var pendingCountText: String {
        let count = model.queuedCount
        let key = count == 1 ? "queue.pendingCount.one" : "queue.pendingCount.many"
        return model.tf(key, count)
    }

    private var historyPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.t("history.title"))
                    .font(.title2.bold())
                Spacer()
                Button(model.t("history.reveal")) {
                    model.revealOutputDirectory()
                }
                Button(model.t("history.clear")) {
                    model.clearHistory()
                }
                .disabled(model.history.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            Divider()

            if model.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text(model.t("history.empty"))
                        .font(.headline)
                    Text(model.t("history.emptyHelp"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.history) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(2)

                        HStack {
                            Text("\(item.mode.displayName(model.language)) · \(item.format)")
                            Spacer()
                            Text(item.completedAt, style: .date)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text(item.filePath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
    }
}
