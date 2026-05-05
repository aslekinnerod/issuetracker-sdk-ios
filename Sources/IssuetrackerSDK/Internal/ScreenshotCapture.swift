import UIKit

enum ScreenshotCapture {
    /// Snapshots the foreground-active window hierarchy. Fast, happens
    /// entirely in memory. Returns nil on platforms without a window
    /// (unit tests, screenshot-extension hosts, etc.).
    @MainActor
    static func captureCurrentWindow() -> UIImage? {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first,
            let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else {
            return nil
        }
        let bounds = window.bounds
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { _ in
            // `afterScreenUpdates: true` is critical — otherwise the
            // capture can race with in-flight animation frames and
            // come out blank or half-rendered.
            window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }
}
