import Foundation

// Persisted reporter identity shown on submitted issues. Stored in
// UserDefaults.standard, which is sandboxed per app — so the same
// person can legitimately appear with different names in two
// different apps that both use this SDK.
//
// The installId is a stable anonymous UUID generated on first read,
// so the server can group reports from the same install even when
// the name is blank, shared, or duplicated across users.
enum ReporterIdentity {
    private static let nameKey = "com.issuetracker.sdk.reporterName"
    private static let installIdKey = "com.issuetracker.sdk.installId"
    private static let nameMaxLength = 80

    static var name: String? {
        guard let raw = UserDefaults.standard.string(forKey: nameKey) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func setName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(String(trimmed.prefix(nameMaxLength)), forKey: nameKey)
    }

    static func clearName() {
        UserDefaults.standard.removeObject(forKey: nameKey)
    }

    // Lazily generated on first read, persisted thereafter. Survives
    // relaunches; removed on app uninstall along with the rest of
    // UserDefaults.
    static var installId: String {
        if let existing = UserDefaults.standard.string(forKey: installIdKey) {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: installIdKey)
        return fresh
    }

    // The dictionary to include under `reporter` in report payloads.
    // Always has installId; name is omitted when not set.
    static func payload() -> [String: Any] {
        var dict: [String: Any] = ["installId": installId]
        if let name { dict["name"] = name }
        return dict
    }
}
