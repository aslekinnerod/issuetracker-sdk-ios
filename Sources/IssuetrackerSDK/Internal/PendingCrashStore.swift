import Foundation

// Holds session markers from sessions that ended unexpectedly, waiting
// for MetricKit to confirm whether the exit was a real crash (OOM,
// watchdog, bad access, etc.) or a benign normal/force-quit.
//
// Heartbeat alone produces too many false positives — most "unfinished"
// sessions are users swiping the app away from the app switcher, which
// looks identical to a crash from the SDK's perspective. We persist
// the marker here and let MetricKit make the call. Unmatched markers
// older than the retention window are discarded silently.
//
// One file per sessionId so we never need a global lock and so partial
// writes can't corrupt unrelated entries.
final class PendingCrashStore {
    static let shared = PendingCrashStore()

    private let directory: URL
    private let retention: TimeInterval = 7 * 24 * 60 * 60

    private init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = base
            .appendingPathComponent("Issuetracker", isDirectory: true)
            .appendingPathComponent("pending", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func add(_ marker: PendingCrashMarker) {
        let url = fileURL(for: marker.sessionId)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(marker) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    func list() -> [PendingCrashMarker] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(PendingCrashMarker.self, from: data)
        }
    }

    func remove(sessionId: String) {
        try? FileManager.default.removeItem(at: fileURL(for: sessionId))
    }

    func prune(now: Date = Date()) {
        for marker in list() {
            if now.timeIntervalSince(marker.startedAt) > retention {
                remove(sessionId: marker.sessionId)
            }
        }
    }

    private func fileURL(for sessionId: String) -> URL {
        directory.appendingPathComponent("\(sessionId).json")
    }
}

struct PendingCrashMarker: Codable {
    let sessionId: String
    let startedAt: Date
    let endedAt: Date?
    let appVersion: String?
    let osVersion: String?
    let lastLifecycleState: LifecycleState
    let breadcrumbs: [Breadcrumb]
}

enum LifecycleState: String, Codable {
    case active
    case inactive
    case background
}
