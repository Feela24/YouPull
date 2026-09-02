import Foundation

struct ToolPaths {
    let ytDLP: URL
    let ffmpeg: URL?
    let ffprobe: URL?
}

enum ToolLocator {
    static func locate() -> ToolPaths? {
        guard let ytDLP = findExecutable(named: "yt-dlp") else { return nil }
        return ToolPaths(
            ytDLP: ytDLP,
            ffmpeg: findExecutable(named: "ffmpeg"),
            ffprobe: findExecutable(named: "ffprobe")
        )
    }

    static func statusText(language: AppLanguage) -> String {
        guard let tools = locate() else {
            return L10n.text("tools.missingYTDLP", language: language)
        }
        if tools.ffmpeg == nil || tools.ffprobe == nil {
            return L10n.text("tools.missingFFmpeg", language: language)
        }
        return L10n.text("tools.ready", language: language)
    }

    /// Universal OpenPull contains a universal yt-dlp and one native FFmpeg pair
    /// for each supported CPU. Because this function is compiled into both slices
    /// of the Universal 2 app, #if arch(...) selects the native helper directory.
    private static var bundledArchitectureDirectory: String? {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return nil
        #endif
    }

    private static func findExecutable(named name: String) -> URL? {
        var candidates: [URL] = []

        if let resources = Bundle.main.resourceURL {
            let bin = resources.appendingPathComponent("bin", isDirectory: true)

            // yt-dlp_macos is Universal 2 and is stored directly in bin/.
            // FFmpeg/FFprobe are stored as thin native binaries in arch folders.
            if let architecture = bundledArchitectureDirectory {
                candidates.append(
                    bin.appendingPathComponent(architecture, isDirectory: true)
                        .appendingPathComponent(name)
                )
            }

            candidates.append(bin.appendingPathComponent(name))
            candidates.append(resources.appendingPathComponent(name))
        }

        // Development fallback. A finished standalone build does not need these.
        let home = FileManager.default.homeDirectoryForCurrentUser
        candidates += [
            URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"),
            URL(fileURLWithPath: "/usr/local/bin/\(name)"),
            home.appendingPathComponent(".local/bin/\(name)"),
            home.appendingPathComponent("bin/\(name)")
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for component in path.split(separator: ":") {
                candidates.append(URL(fileURLWithPath: String(component)).appendingPathComponent(name))
            }
        }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
