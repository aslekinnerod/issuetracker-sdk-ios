import Foundation

// Thin wrapper around URLSession that matches the Firebase Functions
// callable wire format — request body wrapped in `{"data": ...}`,
// response body wrapped in `{"result": ...}`. Unauthenticated, since
// SDK calls use the API key as their only auth.
enum APIClient {
    struct CallableError: LocalizedError {
        let status: Int
        let message: String
        // ADR-0003 Decision 9 structured payload, when the server sends
        // one (i.e. for SDK-callables — older endpoints leave this nil).
        let details: SdkErrorDetails?

        var errorDescription: String? { message }

        /// Convenience: surfaces the typed reason when present.
        var sdkErrorReason: SdkErrorReason? { details?.reason }
    }

    // Decode the `details` object Firebase callable bubbles up under
    // `error.details`. Returns nil for any malformed shape so callers
    // can fall back to the generic message-only error path.
    private static func parseErrorDetails(_ json: [String: Any]) -> SdkErrorDetails? {
        guard let raw = json["details"] as? [String: Any] else { return nil }
        return SdkErrorDetails(json: raw)
    }

    static func call<Response: Decodable>(
        endpoint: URL,
        function: String,
        payload: [String: Any]
    ) async throws -> Response {
        var url = endpoint
        url.appendPathComponent(function)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": payload])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CallableError(status: 0, message: "Invalid response", details: nil)
        }

        // Callable error shape: {"error": {"message": "...", "status": "...", "details": {...}}}
        if http.statusCode >= 400 {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = dict["error"] as? [String: Any] {
                let msg = (err["message"] as? String) ?? "HTTP \(http.statusCode)"
                throw CallableError(
                    status: http.statusCode,
                    message: msg,
                    details: parseErrorDetails(err)
                )
            }
            throw CallableError(status: http.statusCode, message: "HTTP \(http.statusCode)", details: nil)
        }

        let envelope = try JSONDecoder().decode(Envelope<Response>.self, from: data)
        return envelope.result
    }

    // Streaming variant for endpoints where we want to surface upload
    // byte progress to the UI. Uses URLSession.upload(for:from:delegate:)
    // so didSendBodyData fires as the request body is transmitted.
    static func uploadWithProgress<Response: Decodable>(
        endpoint: URL,
        function: String,
        payload: [String: Any],
        onProgress: @MainActor @escaping (Double) -> Void,
        onProcessing: @MainActor @escaping () -> Void
    ) async throws -> Response {
        var url = endpoint
        url.appendPathComponent(function)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONSerialization.data(withJSONObject: ["data": payload])

        let delegate = UploadProgressDelegate { fraction in
            Task { @MainActor in onProgress(fraction) }
        }
        let session = URLSession(configuration: .default)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.upload(for: request, from: body, delegate: delegate)

        // All bytes shipped; server is now doing post-upload work.
        await MainActor.run { onProcessing() }

        guard let http = response as? HTTPURLResponse else {
            throw CallableError(status: 0, message: "Invalid response", details: nil)
        }
        if http.statusCode >= 400 {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = dict["error"] as? [String: Any] {
                let msg = (err["message"] as? String) ?? "HTTP \(http.statusCode)"
                throw CallableError(
                    status: http.statusCode,
                    message: msg,
                    details: parseErrorDetails(err)
                )
            }
            throw CallableError(status: http.statusCode, message: "HTTP \(http.statusCode)", details: nil)
        }

        let envelope = try JSONDecoder().decode(Envelope<Response>.self, from: data)
        return envelope.result
    }

    // Generic envelope can't live inside the generic call function —
    // Swift forbids nested generic types. Placed alongside it.
    private struct Envelope<T: Decodable>: Decodable { let result: T }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
