import Foundation

// Thin wrapper around URLSession that matches the Firebase Functions
// callable wire format — request body wrapped in `{"data": ...}`,
// response body wrapped in `{"result": ...}`. Unauthenticated, since
// SDK calls use the API key as their only auth.
enum APIClient {
    struct CallableError: LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message }
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
            throw CallableError(status: 0, message: "Invalid response")
        }

        // Callable error shape: {"error": {"message": "...", "status": "..."}}
        if http.statusCode >= 400 {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = dict["error"] as? [String: Any],
               let msg = err["message"] as? String {
                throw CallableError(status: http.statusCode, message: msg)
            }
            throw CallableError(status: http.statusCode, message: "HTTP \(http.statusCode)")
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
            throw CallableError(status: 0, message: "Invalid response")
        }
        if http.statusCode >= 400 {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = dict["error"] as? [String: Any],
               let msg = err["message"] as? String {
                throw CallableError(status: http.statusCode, message: msg)
            }
            throw CallableError(status: http.statusCode, message: "HTTP \(http.statusCode)")
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
