import Foundation
import UIKit

// Heartbeat-style crash detection without signal handlers. The rules:
//
// 1. On SDK configure, we write a "session-alive" marker to disk.
// 2. On willTerminate (which iOS fires for clean shutdowns), we
//    remove the marker.
// 3. At the next configure, if the marker is still there, we treat
//    the previous session as having ended unexpectedly — crash, OOM
//    kill, or force-quit. False positives from force-quit are
//    acceptable for MVP; triagers can dismiss.
//
// Breadcrumbs are read from BreadcrumbStore and attached to the
// auto-generated crash report before the new session overwrites them.
struct SessionMarker: Codable {
    let sessionId: String
    let startedAt: Date
    let appVersion: String?
    let osVersion: String?
}

@MainActor
final class CrashDetector {
    static let shared = CrashDetector()

    private let fileURL: URL
    private var currentMarker: SessionMarker?

    private init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Issuetracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("session-alive.json")
    }

    // Returns the previous session's marker IF it exists — meaning
    // the previous session didn't reach willTerminate. Caller reports
    // it, then calls startNewSession() to install a fresh one.
    func readUnfinishedSession() -> SessionMarker? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(SessionMarker.self, from: data)
    }

    // Writes a new session marker and hooks up the cleanup handler.
    // Safe to call once per configure — repeats are a no-op.
    func startNewSession() {
        guard currentMarker == nil else { return }
        let marker = SessionMarker(
            sessionId: UUID().uuidString,
            startedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            osVersion: UIDevice.current.systemVersion
        )
        currentMarker = marker
        persist(marker)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    // Consumes the stale marker (after reporting it). Call this
    // AFTER startNewSession so the new marker isn't removed too.
    func clearUnfinishedMarker() {
        try? FileManager.default.removeItem(at: fileURL)
        // Re-persist the current marker since remove wiped the file.
        if let currentMarker {
            persist(currentMarker)
        }
    }

    @objc private func handleWillTerminate() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func persist(_ marker: SessionMarker) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(marker) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
