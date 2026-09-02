import Foundation

final class HistoryStore {
    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true)) ?? fm.homeDirectoryForCurrentUser
        let directory = base.appendingPathComponent("OpenPull", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("history.json")
    }

    func load() -> [HistoryItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            return []
        }
        return items.sorted { $0.completedAt > $1.completedAt }
    }

    func save(_ items: [HistoryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
