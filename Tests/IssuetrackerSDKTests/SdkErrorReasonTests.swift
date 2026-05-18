import XCTest
@testable import IssuetrackerSDK

// Contract tests for the SDK error wire format. The raw values here
// MUST match @issuetracker/shared SdkErrorReasonSchema byte-for-byte
// — any drift breaks the lifecycle transition logic in LifecycleStore.
//
// See ADR-0003 Decision 9.
final class SdkErrorReasonTests: XCTestCase {

    func testCanonicalReasonsAreAllRepresented() {
        // Mirror of the canonical seven from the shared schema. The
        // five SDKs share this contract; drift breaks deployed clients.
        let canonical: Set<String> = [
            "project_deleted",
            "project_not_found",
            "api_key_revoked",
            "workspace_suspended",
            "invalid_api_key",
            "quota_exceeded",
            "transient",
        ]
        let actual = Set(SdkErrorReason.allCases.map(\.rawValue))
        XCTAssertEqual(actual, canonical)
    }

    func testWorkspaceDeletedMisnomerIsRejected() {
        // The OPERATIONS-FOLLOWUPS doc used "WORKSPACE_DELETED" for a
        // week as the wire name — it never was. A server typo here
        // MUST NOT enter the lifecycle as TERMINATED.
        XCTAssertNil(SdkErrorReason(rawValue: "workspace_deleted"))
        XCTAssertNil(SdkErrorReason(rawValue: "WORKSPACE_SUSPENDED"))
        XCTAssertNil(SdkErrorReason(rawValue: ""))
    }

    func testRecoverableMappingMatchesSharedSchema() {
        XCTAssertTrue(SdkErrorReason.quotaExceeded.isRecoverable)
        XCTAssertTrue(SdkErrorReason.transient.isRecoverable)
        XCTAssertFalse(SdkErrorReason.projectDeleted.isRecoverable)
        XCTAssertFalse(SdkErrorReason.projectNotFound.isRecoverable)
        XCTAssertFalse(SdkErrorReason.apiKeyRevoked.isRecoverable)
        XCTAssertFalse(SdkErrorReason.workspaceSuspended.isRecoverable)
        XCTAssertFalse(SdkErrorReason.invalidApiKey.isRecoverable)
    }

    func testParseWellFormedWorkspaceSuspended() {
        let details = SdkErrorDetails(json: [
            "error": "workspace_suspended",
            "recoverable": false,
        ])
        XCTAssertEqual(details?.reason, .workspaceSuspended)
        XCTAssertEqual(details?.recoverable, false)
        XCTAssertNil(details?.deletedAt)
        XCTAssertNil(details?.retryAfterSeconds)
    }

    func testParseProjectDeletedWithDeletedAtMillis() {
        let millis: Double = 1747000000000
        let details = SdkErrorDetails(json: [
            "error": "project_deleted",
            "recoverable": false,
            "deletedAt": millis,
        ])
        XCTAssertEqual(details?.reason, .projectDeleted)
        XCTAssertNotNil(details?.deletedAt)
        XCTAssertEqual(
            details?.deletedAt?.timeIntervalSince1970 ?? 0,
            millis / 1000,
            accuracy: 0.001
        )
    }

    func testParseQuotaExceededWithRetryAfterSeconds() {
        let details = SdkErrorDetails(json: [
            "error": "quota_exceeded",
            "recoverable": true,
            "retryAfterSeconds": 30,
        ])
        XCTAssertEqual(details?.reason, .quotaExceeded)
        XCTAssertEqual(details?.retryAfterSeconds, 30)
    }

    func testParseUnknownReasonReturnsNil() {
        XCTAssertNil(SdkErrorDetails(json: [
            "error": "workspace_deleted",
            "recoverable": false,
        ]))
    }

    func testParseMissingRecoverableReturnsNil() {
        XCTAssertNil(SdkErrorDetails(json: [
            "error": "project_deleted",
        ]))
    }

    func testParseWrongTypeRecoverableReturnsNil() {
        XCTAssertNil(SdkErrorDetails(json: [
            "error": "project_deleted",
            "recoverable": "false",
        ]))
    }

    func testParseIgnoresExtraFields() {
        let details = SdkErrorDetails(json: [
            "error": "project_deleted",
            "recoverable": false,
            "unexpected": "value",
            "foo": 42,
        ])
        XCTAssertEqual(details?.reason, .projectDeleted)
    }
}
