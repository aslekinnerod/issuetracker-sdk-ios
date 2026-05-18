import CoreMotion
import Foundation
import UIKit

// Detects shake via CoreMotion accelerometer rather than UIKit
// motion events. Avoids the UIWindow / responder-chain swizzling
// rabbit hole — the accelerometer is always on, and we just watch
// for a magnitude spike above a threshold.
//
// Note: simulator's `Device → Shake` sends a UIKit motion event, not
// an accelerometer spike, so shake-to-report works only on real
// devices. Simulator users can call `Issuetracker.report()` from a
// button during development.
enum ShakeObserver {
    @MainActor private static var onShake: (() -> Void)?
    private static let motionManager = CMMotionManager()
    private static let queue = OperationQueue()
    // Tuned empirically — a typical wrist shake produces peak
    // acceleration around 2.5–3g, while normal walking stays under
    // ~1.5g. The debounce prevents a single shake firing multiple
    // times.
    private static let threshold: Double = 2.5
    private static let debounceInterval: TimeInterval = 1.5
    @MainActor private static var lastFiredAt: Date = .distantPast

    @MainActor
    static func install(onShake handler: @escaping () -> Void) {
        self.onShake = handler
        start()
    }

    @MainActor
    static var isInstalled: Bool { onShake != nil }

    @MainActor
    private static func start() {
        guard motionManager.isAccelerometerAvailable else { return }
        guard !motionManager.isAccelerometerActive else { return }
        motionManager.accelerometerUpdateInterval = 1.0 / 20.0 // 20 Hz — plenty for shake detection
        motionManager.startAccelerometerUpdates(to: queue) { data, _ in
            guard let data else { return }
            let a = data.acceleration
            let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            if magnitude >= threshold {
                Task { @MainActor in fire() }
            }
        }
    }

    @MainActor
    private static func fire() {
        let now = Date()
        if now.timeIntervalSince(lastFiredAt) < debounceInterval { return }
        lastFiredAt = now
        onShake?()
    }
}
