import XCTest
@testable import IssuetrackerSDK

/// End-to-end parse of the ADR-0003 Decision 9 error contract, driven
/// through the real `APIClient` callable-envelope decoder against a
/// stubbed transport.
///
/// `SdkErrorReasonTests` covers the `SdkErrorDetails` value type in
/// isolation. This suite covers the layer above it: given the bytes a
/// Firebase callable actually puts on the wire, does the SDK end up
/// with the right `SdkErrorReason` — and does it get there from
/// `details.error` rather than from the HTTP status?
///
/// Sibling suites: `sdk-web/src/api.test.ts`, `sdk-android`'s
/// `ApiClientErrorContractTest`. Keep the case list in lockstep.
final class SdkErrorWireContractTests: XCTestCase {

    private struct ConfigResult: Decodable { let requireTesterAttestation: Bool }

    private let endpoint = URL(string: "https://issuetracker-api-dev.web.app/v1")!
    private let function = "createIssueFromSdk"

    override func setUp() {
        super.setUp()
        CallableStub.start()
    }

    override func tearDown() {
        CallableStub.stop()
        super.tearDown()
    }

    /// Performs the call and returns the `CallableError` it threw.
    private func callAndCaptureError(
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> APIClient.CallableError? {
        do {
            let _: ConfigResult = try await APIClient.call(
                endpoint: endpoint,
                function: function,
                payload: ["apiKey": "it_dev_stub"]
            )
            XCTFail("expected the call to throw", file: file, line: line)
            return nil
        } catch let err as APIClient.CallableError {
            return err
        } catch {
            XCTFail("expected CallableError, got \(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: - The canonical matrix

    func testEveryCanonicalReasonSurvivesTheWire() async {
        // Reason, the HTTP status Firebase maps its callable code to,
        // and whether the SDK must treat it as terminal.
        // ADR-0003 Decision 9 §1 + §2.
        let matrix: [(error: String, status: Int, reason: SdkErrorReason, terminal: Bool)] = [
            ("project_deleted", 404, .projectDeleted, true),
            ("project_not_found", 404, .projectNotFound, true),
            ("api_key_revoked", 403, .apiKeyRevoked, true),
            ("workspace_suspended", 403, .workspaceSuspended, true),
            ("invalid_api_key", 401, .invalidApiKey, true),
            ("quota_exceeded", 429, .quotaExceeded, false),
            ("transient", 503, .transient, false),
        ]

        for row in matrix {
            CallableStub.enqueueError(
                function: function,
                status: row.status,
                error: row.error,
                recoverable: !row.terminal
            )
            let err = await callAndCaptureError()
            XCTAssertEqual(err?.sdkErrorReason, row.reason, "\(row.error)")
            XCTAssertEqual(err?.status, row.status, "\(row.error)")
            XCTAssertEqual(err?.details?.recoverable, !row.terminal, "\(row.error)")
            XCTAssertEqual(err?.sdkErrorReason?.isTerminal, row.terminal, "\(row.error)")
        }
    }

    func testProjectDeletedCarriesDeletedAt() async {
        let millis: Double = 1_747_000_000_000
        CallableStub.enqueueError(
            function: function,
            status: 404,
            error: "project_deleted",
            recoverable: false,
            deletedAt: millis
        )
        let err = await callAndCaptureError()
        XCTAssertEqual(err?.sdkErrorReason, .projectDeleted)
        XCTAssertEqual(
            err?.details?.deletedAt?.timeIntervalSince1970 ?? 0,
            millis / 1000,
            accuracy: 0.001
        )
    }

    func testQuotaExceededCarriesRetryAfterSeconds() async {
        CallableStub.enqueueError(
            function: function,
            status: 429,
            error: "quota_exceeded",
            recoverable: true,
            retryAfterSeconds: 42
        )
        let err = await callAndCaptureError()
        XCTAssertEqual(err?.sdkErrorReason, .quotaExceeded)
        XCTAssertEqual(err?.details?.retryAfterSeconds, 42)
    }

    // MARK: - details.error, not the HTTP status

    /// A terminal reason delivered under a status that is *not* the one
    /// the ADR documents must still read as terminal. If anyone ever
    /// rewrites the dispatch as `if status == 404 || status == 403`,
    /// this is the test that catches it.
    func testTerminalReasonIsHonouredUnderAnUnexpectedStatus() async {
        for status in [400, 409, 500, 503] {
            CallableStub.enqueueError(
                function: function,
                status: status,
                error: "project_deleted",
                recoverable: false
            )
            let err = await callAndCaptureError()
            XCTAssertEqual(err?.sdkErrorReason, .projectDeleted, "status \(status)")
            XCTAssertEqual(err?.sdkErrorReason?.isTerminal, true, "status \(status)")
        }
    }

    /// The mirror image: a *recoverable* reason delivered under 404 /
    /// 403 / 401 must not be terminal. Status-based dispatch would kill
    /// the SDK here — permanently, for every deployed install — on what
    /// is really a rate limit.
    func testRecoverableReasonUnderATerminalStatusIsNotTerminal() async {
        for status in [401, 403, 404] {
            CallableStub.enqueueError(
                function: function,
                status: status,
                error: "quota_exceeded",
                recoverable: true
            )
            let err = await callAndCaptureError()
            XCTAssertEqual(err?.sdkErrorReason, .quotaExceeded, "status \(status)")
            XCTAssertEqual(err?.sdkErrorReason?.isTerminal, false, "status \(status)")
        }
    }

    /// A bare 404 with no `details` — a CDN error page, a bad path, a
    /// pre-Decision-9 deployment — carries no reason, so nothing can
    /// terminate on it.
    func testBareErrorWithoutDetailsCarriesNoReason() async {
        CallableStub.enqueueError(
            function: function,
            status: 404,
            error: nil,
            recoverable: nil,
            includeDetails: false
        )
        let err = await callAndCaptureError()
        XCTAssertNil(err?.details)
        XCTAssertNil(err?.sdkErrorReason)
        XCTAssertEqual(err?.status, 404)
    }

    /// A dead network is not a contract signal. It must surface as a
    /// transport error, never as a `CallableError` — otherwise an
    /// offline device could be mistaken for a deleted project.
    func testTransportFailureIsNotACallableError() async {
        do {
            let _: ConfigResult = try await APIClient.call(
                endpoint: endpoint,
                function: "unscriptedFunction",
                payload: [:]
            )
            XCTFail("expected the call to throw")
        } catch is APIClient.CallableError {
            XCTFail("a transport failure must not masquerade as a callable error")
        } catch {
            // URLError — the SUSPENDED/retry path, never TERMINATED.
            XCTAssertTrue(error is URLError)
        }
    }

    // MARK: - Forward compatibility

    /// Deployed SDKs outlive the server by years. If the server ever
    /// adds a reason this build has never heard of, the parse is
    /// all-or-nothing today: `SdkErrorDetails.init?` fails on the
    /// unknown enum value and the whole `details` object is discarded,
    /// including its authoritative `recoverable: false`.
    ///
    /// ADR-0003 Decision 9 §1 says clients "treat `details.recoverable`
    /// as authoritative". This documents the gap — see the audit
    /// finding on `SdkErrorReason.swift:73`.
    func testUnknownFutureReasonLosesItsRecoverableFlag() async {
        CallableStub.enqueueError(
            function: function,
            status: 403,
            error: "workspace_liquidated",
            recoverable: false
        )
        let err = await callAndCaptureError()
        XCTAssertNil(err?.sdkErrorReason, "unknown reason is not in this build's enum")

        XCTExpectFailure(
            "GAP (ADR-0003 D9 §1): an unknown reason carrying recoverable:false " +
            "is dropped entirely, so a future non-recoverable reason will not " +
            "terminate deployed clients. SdkErrorDetails.init? should retain the " +
            "recoverable flag independently of the enum parse."
        ) {
            XCTAssertEqual(
                err?.details?.recoverable, false,
                "recoverable:false must survive even when the reason is unknown"
            )
        }
    }
}
