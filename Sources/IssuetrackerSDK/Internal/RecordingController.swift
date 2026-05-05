import Foundation
import ReplayKit
import UIKit

// Thin async/await wrapper around RPScreenRecorder. ReplayKit only
// captures the hosting app's own UI (sandboxed) — which is exactly
// what we want for SDK consumers reporting bugs against a single app.
//
// The first time a user starts recording, iOS presents a permission
// prompt for screen capture + microphone. Decline = we get a failure
// callback and surface the error in the report sheet.
enum RecordingError: Error, LocalizedError {
    case unavailable
    case alreadyRecording
    case permissionDenied
    case noOutputFile
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Screen recording isn't available on this device."
        case .alreadyRecording: return "A recording is already in progress."
        case .permissionDenied: return "Screen recording permission was denied."
        case .noOutputFile: return "The recording finished but no file was produced."
        case .underlying(let err): return err.localizedDescription
        }
    }
}

@MainActor
final class RecordingController {
    static let shared = RecordingController()

    private let recorder = RPScreenRecorder.shared()
    private(set) var isRecording: Bool = false
    private var currentOutputURL: URL?

    private init() {}

    var isAvailable: Bool {
        return recorder.isAvailable
    }

    func start(withMicrophone: Bool = false) async throws {
        guard !isRecording else { throw RecordingError.alreadyRecording }
        guard recorder.isAvailable else { throw RecordingError.unavailable }

        recorder.isMicrophoneEnabled = withMicrophone

        try await withCheckedThrowingContinuation { [recorder] (cont: CheckedContinuation<Void, Error>) in
            recorder.startRecording { error in
                if let error {
                    // ReplayKit uses NSError — map the most common
                    // permission failure for clearer UX.
                    let ns = error as NSError
                    if ns.domain == RPRecordingErrorDomain && ns.code == -5801 {
                        cont.resume(throwing: RecordingError.permissionDenied)
                    } else {
                        cont.resume(throwing: RecordingError.underlying(error))
                    }
                    return
                }
                cont.resume()
            }
        }
        // Only marked as recording once RPScreenRecorder confirms.
        isRecording = true
    }

    // Stops the active recording and writes the captured movie to a
    // file in the temp directory. Caller owns the returned URL and
    // should move/copy it to their persistence layer before the temp
    // dir is reaped.
    func stop() async throws -> URL {
        guard isRecording else { throw RecordingError.alreadyRecording }

        let fileName = "issuetracker-recording-\(UUID().uuidString).mp4"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        currentOutputURL = url

        try await withCheckedThrowingContinuation { [recorder] (cont: CheckedContinuation<Void, Error>) in
            recorder.stopRecording(withOutput: url) { error in
                if let error {
                    cont.resume(throwing: RecordingError.underlying(error))
                } else {
                    cont.resume()
                }
            }
        }

        isRecording = false
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RecordingError.noOutputFile
        }
        return url
    }

    // Best-effort cancel. RPScreenRecorder has no first-class
    // cancel — we stop + delete the file.
    func cancel() async {
        guard isRecording else { return }
        let fileName = "issuetracker-recording-discard-\(UUID().uuidString).mp4"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        isRecording = false
        await withCheckedContinuation { [recorder] cont in
            recorder.stopRecording(withOutput: url) { _ in
                try? FileManager.default.removeItem(at: url)
                cont.resume()
            }
        }
    }
}

