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

    // Generic envelope can't live inside the generic call function —
    // Swift forbids nested generic types. Placed alongside it.
    private struct Envelope<T: Decodable>: Decodable { let result: T }
}
