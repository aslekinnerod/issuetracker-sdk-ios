import Foundation
import UIKit

// Gathers non-PII device + app metadata that's useful when triaging
// a bug report. Everything here is derivable from public APIs that
// don't require special entitlements. Deliberately avoids
// `UIDevice.current.name` and anything tied to the user's identity —
// that would turn the SDK into a privacy risk for integrators.
enum ContextCollector {
    @MainActor
    static func collect() -> [String: String] {
        let device = UIDevice.current
        let bundle = Bundle.main
        var out: [String: String] = [
            "platform": "iOS",
            "osVersion": device.systemVersion,
            "locale": Locale.current.identifier,
            "timeZone": TimeZone.current.identifier,
        ]
        if let model = modelIdentifier() { out["deviceModel"] = model }
        if let bundleId = bundle.bundleIdentifier { out["appBundleId"] = bundleId }
        if let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
            out["appVersion"] = version
        }
        if let build = bundle.infoDictionary?["CFBundleVersion"] as? String {
            out["appBuild"] = build
        }
        return out
    }

    /// Reads the hardware identifier — e.g. `iPhone16,1` — via `uname(3)`.
    /// `UIDevice.model` only returns the generic family name ("iPhone").
    private static func modelIdentifier() -> String? {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return partial }
            return partial + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? nil : identifier
    }
}
