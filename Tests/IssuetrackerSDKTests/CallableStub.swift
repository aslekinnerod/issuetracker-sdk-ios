import Foundation

/// A fake Firebase-callable surface.
///
/// The ADR-0003 Decision 9 contract is a *wire* contract — the SDK
/// must dispatch on the structured `details.error` object that rides
/// inside the callable error envelope, not on the HTTP status. Testing
/// that with hand-built `SdkErrorDetails` values would skip exactly
/// the layer where the contract lives (`APIClient`'s envelope parse),
/// so these suites drive the real code path and stub the transport
/// instead.
///
/// Registered globally via `URLProtocol.registerClass`, which
/// intercepts `URLSession.shared` — the session `APIClient.call` uses.
/// (`APIClient.uploadWithProgress` builds its own session with a
/// custom configuration and is therefore *not* interceptable this
/// way; see `LifecycleTerminationTests` for what that costs us.)
///
/// Responses are queued per callable name (the last path component of
/// the request URL), so a test can script `getSdkConfig` and
/// `createIssueFromSdk` independently and assert on how many requests
/// each one actually received.
/// Thread-safe reference box for counting callbacks fired from
/// `@Sendable` closures (NotificationCenter observer blocks).
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        get { lock.withLock { count } }
        set { lock.withLock { count = newValue } }
    }
}

final class CallableStub: URLProtocol {

    struct Canned {
        let status: Int
        let body: Data
    }

    private static let lock = NSLock()
    private static var queued: [String: [Canned]] = [:]
    private static var requestLog: [String] = []

    // MARK: - Lifecycle

    static func start() {
        lock.lock()
        queued = [:]
        requestLog = []
        lock.unlock()
        URLProtocol.registerClass(CallableStub.self)
    }

    static func stop() {
        URLProtocol.unregisterClass(CallableStub.self)
        lock.lock()
        queued = [:]
        requestLog = []
        lock.unlock()
    }

    // MARK: - Scripting

    /// Queues one callable *error* response.
    ///
    /// - Parameters:
    ///   - status: HTTP status Firebase maps the callable code to.
    ///     Deliberately independent of `error` so tests can prove the
    ///     SDK ignores it.
    ///   - error: value of `details.error`; `nil` omits the field.
    ///   - recoverable: value of `details.recoverable`; `nil` omits it.
    ///   - includeDetails: `false` sends a bare callable error with no
    ///     `details` object at all — the shape older endpoints and
    ///     infrastructure-level failures produce.
    static func enqueueError(
        function: String,
        status: Int,
        error: String?,
        recoverable: Bool?,
        deletedAt: Double? = nil,
        retryAfterSeconds: Int? = nil,
        includeDetails: Bool = true,
        message: String = "stubbed failure"
    ) {
        var envelope: [String: Any] = [
            "message": message,
            "status": "STUBBED",
        ]
        if includeDetails {
            var details: [String: Any] = [:]
            if let error { details["error"] = error }
            if let recoverable { details["recoverable"] = recoverable }
            if let deletedAt { details["deletedAt"] = deletedAt }
            if let retryAfterSeconds { details["retryAfterSeconds"] = retryAfterSeconds }
            envelope["details"] = details
        }
        let body = try! JSONSerialization.data(withJSONObject: ["error": envelope])
        enqueue(function: function, canned: Canned(status: status, body: body))
    }

    /// Queues one successful callable response (`{"result": ...}`).
    static func enqueueSuccess(function: String, result: [String: Any]) {
        let body = try! JSONSerialization.data(withJSONObject: ["result": result])
        enqueue(function: function, canned: Canned(status: 200, body: body))
    }

    private static func enqueue(function: String, canned: Canned) {
        lock.lock()
        queued[function, default: []].append(canned)
        lock.unlock()
    }

    /// How many requests this callable actually received. `0` is the
    /// assertion that matters for "a TERMINATED SDK stops talking to
    /// the server".
    static func requestCount(for function: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestLog.filter { $0 == function }.count
    }

    static var totalRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestLog.count
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let function = request.url?.lastPathComponent ?? ""

        CallableStub.lock.lock()
        CallableStub.requestLog.append(function)
        let canned: Canned? = {
            guard var pending = CallableStub.queued[function], !pending.isEmpty else { return nil }
            let next = pending.removeFirst()
            CallableStub.queued[function] = pending
            return next
        }()
        CallableStub.lock.unlock()

        guard let canned, let url = request.url else {
            // Nothing scripted: behave like a dead network rather than
            // silently succeeding, so an unexpected call is loud.
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: canned.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: canned.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
