import Foundation
import UIKit

// Heartbeat-style crash detection without signal handlers. The rules:
//
// 1. On SDK configure, we write a "session-alive" marker to disk.
// 2. On lifecycle events (background/foreground/active/inactive) we
//    refresh the marker so it always reflects the latest known state
//    plus a recent timestamp.
// 3. On willTerminate (which iOS fires for clean shutdowns), we
//    remove the marker.
// 4. At the next configure, if the marker is still there, the previous
//    session ended unexpectedly. The marker alone CAN'T distinguish
//    crash, OOM, watchdog, or force-quit — we hand it to MetricKit
//    via PendingCrashStore for confirmation.
struct SessionMarker: Codable {
    let sessionId: String
    let startedAt: Date
    var endedAt: Date
    let appVersion: String?
    let osVersion: String?
    var lastLifecycleState: LifecycleState
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
    // the previous session didn't reach willTerminate. Caller moves
    // it to PendingCrashStore, then calls startNewSession() to install
    // a fresh one.
    func readUnfinishedSession() -> SessionMarker? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(SessionMarker.self, from: data)
    }

    // Writes a new session marker and hooks up the lifecycle handlers.
    // Safe to call once per configure — repeats are a no-op.
    func startNewSession() {
        guard currentMarker == nil else { return }
        let now = Date()
        let marker = SessionMarker(
            sessionId: UUID().uuidString,
            startedAt: now,
            endedAt: now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            osVersion: UIDevice.current.systemVersion,
            lastLifecycleState: .active
        )
        currentMarker = marker
        persist(marker)

        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(handleWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    // Consumes the stale marker (after handing it to PendingCrashStore).
    // Call this AFTER startNewSession so the new marker isn't removed.
    func clearUnfinishedMarker() {
        try? FileManager.default.removeItem(at: fileURL)
        if let currentMarker {
            persist(currentMarker)
        }
    }

    @objc private func handleWillTerminate() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    @objc private func handleDidBecomeActive() {
        updateLifecycle(.active)
    }

    @objc private func handleWillResignActive() {
        updateLifecycle(.inactive)
    }

    @objc private func handleDidEnterBackground() {
        updateLifecycle(.background)
    }

    @objc private func handleWillEnterForeground() {
        updateLifecycle(.inactive)
    }

    private func updateLifecycle(_ state: LifecycleState) {
        guard var marker = currentMarker else { return }
        marker.lastLifecycleState = state
        marker.endedAt = Date()
        currentMarker = marker
        persist(marker)
    }

    private func persist(_ marker: SessionMarker) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(marker) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
