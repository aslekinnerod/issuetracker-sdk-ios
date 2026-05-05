import Foundation

// Simple ring buffer of the 5 most recent user actions. Persisted to
// disk on each add so the breadcrumbs survive a crash and can be
// attached to the auto-generated crash report on the next launch.
//
// We use Application Support instead of Caches or tmp because the
// system won't reap it between sessions — breadcrumbs written just
// before a crash MUST still be there tomorrow.
struct Breadcrumb: Codable, Equatable {
    let timestamp: Date
    let action: String
    let metadata: [String: String]?
}

final class BreadcrumbStore {
    static let shared = BreadcrumbStore()

    private let maxEntries = 5
    private let fileURL: URL
    private let queue = DispatchQueue(label: "issuetracker.breadcrumbs", qos: .utility)
    private var entries: [Breadcrumb] = []

    private init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Issuetracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("breadcrumbs.json")
        self.entries = Self.load(from: fileURL)
    }

    func record(_ action: String, metadata: [String: String]?) {
        let trimmed = action.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let capped = String(trimmed.prefix(80))
        let cappedMeta = metadata.map { dict in
            Dictionary(uniqueKeysWithValues:
                dict.prefix(5).map { (String($0.key.prefix(64)), String($0.value.prefix(256))) }
            )
        }
        queue.async {
            self.entries.append(Breadcrumb(
                timestamp: Date(),
                action: capped,
                metadata: cappedMeta?.isEmpty == true ? nil : cappedMeta
            ))
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
            Self.persist(self.entries, to: self.fileURL)
        }
    }

    // Snapshot for inclusion in a report. Safe to call from any queue.
    func snapshot() -> [Breadcrumb] {
        return queue.sync { entries }
    }

    // Clear after a report that consumed them (e.g. an auto-sent
    // crash report) so the next session starts fresh.
    func clear() {
        queue.async {
            self.entries = []
            try? FileManager.default.removeItem(at: self.fileURL)
        }
    }

    private static func load(from url: URL) -> [Breadcrumb] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode([Breadcrumb].self, from: data)) ?? []
    }

    private static func persist(_ entries: [Breadcrumb], to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
