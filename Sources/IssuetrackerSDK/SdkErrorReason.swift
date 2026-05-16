import Foundation

/// Machine-readable reason for an SDK-callable failure. The raw values
/// match the server-side `SdkErrorReasonSchema` in
/// `@issuetracker/shared` byte-for-byte — they are the wire contract
/// across all five SDKs. See ADR-0003 Decision 9.
///
/// Recoverable reasons (`quotaExceeded`, `transient`) leave the SDK in
/// the `OK` state and let the existing per-report flow retry on next
/// trigger. Non-recoverable reasons transition the SDK into a one-way
/// `TERMINATED` state — see ``LifecycleStore``.
public enum SdkErrorReason: String, Sendable, CaseIterable {
    case projectDeleted = "project_deleted"
    case projectNotFound = "project_not_found"
    case apiKeyRevoked = "api_key_revoked"
    case workspaceSuspended = "workspace_suspended"
    case invalidApiKey = "invalid_api_key"
    case quotaExceeded = "quota_exceeded"
    case transient

    public var isRecoverable: Bool {
        switch self {
        case .quotaExceeded, .transient:
            return true
        case .projectDeleted,
             .projectNotFound,
             .apiKeyRevoked,
             .workspaceSuspended,
             .invalidApiKey:
            return false
        }
    }
}

/// Structured failure payload parsed out of the server's `HttpsError`
/// `details` object. Internal — host apps only see ``SdkErrorReason``
/// via the `onConfigurationError` callback.
struct SdkErrorDetails: Sendable {
    let reason: SdkErrorReason
    let recoverable: Bool
    let deletedAt: Date?
    let retryAfterSeconds: Int?

    init?(json: [String: Any]) {
        guard
            let errorStr = json["error"] as? String,
            let reason = SdkErrorReason(rawValue: errorStr),
            let recoverable = json["recoverable"] as? Bool
        else {
            return nil
        }
        self.reason = reason
        self.recoverable = recoverable
        // Server sends `deletedAt` as epoch milliseconds (matches the
        // shared schema's number-typed field).
        if let atMillis = json["deletedAt"] as? Double {
            self.deletedAt = Date(timeIntervalSince1970: atMillis / 1000)
        } else {
            self.deletedAt = nil
        }
        self.retryAfterSeconds = json["retryAfterSeconds"] as? Int
    }
}
