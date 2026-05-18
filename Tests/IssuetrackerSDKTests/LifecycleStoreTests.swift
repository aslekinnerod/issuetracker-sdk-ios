import XCTest
@testable import IssuetrackerSDK

// LifecycleStore is a singleton in production, but exposes an
// internal init that takes UserDefaults so tests can run against a
// throwaway suite for isolation. Same contract as the sdk-web suite
// in sdk-web/src/lifecycle.test.ts — and they must stay in lockstep.
@MainActor
final class LifecycleStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "io.issuetracker.sdk.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testStartsInOkState() {
        let store = LifecycleStore(defaults: defaults)
        XCTAssertFalse(store.isTerminated)
    }

    func testTransitionsToTerminatedOnNonRecoverableSignal() {
        let store = LifecycleStore(defaults: defaults)
        store.transitionToTerminated(reason: .workspaceSuspended, callback: nil)
        XCTAssertTrue(store.isTerminated)
    }

    func testCallbackFiresExactlyOnceOnFirstTransition() {
        let store = LifecycleStore(defaults: defaults)
        var callCount = 0
        var receivedReason: SdkErrorReason?
        let cb: (SdkErrorReason) -> Void = { reason in
            callCount += 1
            receivedReason = reason
        }
        store.transitionToTerminated(reason: .workspaceSuspended, callback: cb)
        store.transitionToTerminated(reason: .projectDeleted, callback: cb)
        store.transitionToTerminated(reason: .apiKeyRevoked, callback: cb)
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(receivedReason, .workspaceSuspended)
    }

    func testPersistsTerminatedReasonToDefaults() {
        let store = LifecycleStore(defaults: defaults)
        store.transitionToTerminated(reason: .projectDeleted, callback: nil)
        XCTAssertEqual(
            defaults.string(forKey: "io.issuetracker.sdk.terminatedReason"),
            "project_deleted"
        )
        XCTAssertGreaterThan(
            defaults.double(forKey: "io.issuetracker.sdk.terminatedAt"),
            0
        )
    }

    func testRehydratesTerminatedFromDefaultsOnFreshInit() {
        // Simulate a previous launch having persisted the terminated
        // state, then a process restart. A fresh init must read the
        // marker and refuse further reports immediately.
        defaults.set("workspace_suspended", forKey: "io.issuetracker.sdk.terminatedReason")
        defaults.set(1747000000.0, forKey: "io.issuetracker.sdk.terminatedAt")

        let store = LifecycleStore(defaults: defaults)
        XCTAssertTrue(store.isTerminated)
    }

    func testIgnoresMalformedPersistedReason() {
        defaults.set("workspace_deleted", forKey: "io.issuetracker.sdk.terminatedReason")
        defaults.set(1747000000.0, forKey: "io.issuetracker.sdk.terminatedAt")

        let store = LifecycleStore(defaults: defaults)
        XCTAssertFalse(store.isTerminated)
    }

    func testPreservesFirstReasonOnSecondSignal() {
        // Server says workspace_suspended first; a later report
        // somehow gets project_deleted. The lifecycle keeps the
        // first reason — the audit value is which signal caused
        // termination, not the most recent one.
        let store = LifecycleStore(defaults: defaults)
        store.transitionToTerminated(reason: .workspaceSuspended, callback: nil)
        store.transitionToTerminated(reason: .projectDeleted, callback: nil)
        XCTAssertEqual(
            defaults.string(forKey: "io.issuetracker.sdk.terminatedReason"),
            "workspace_suspended"
        )
    }
}
