import XCTest
@testable import IssuetrackerSDK

// AttestationStore is a singleton in production, but exposes an
// internal init that takes UserDefaults so tests can run against a
// throwaway suite for isolation. Must stay in lockstep with the
// sdk-web suite in sdk-web/src/attestation.test.ts.
@MainActor
final class AttestationStoreTests: XCTestCase {

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

    private func runtime(apiKey: String) -> Runtime {
        Runtime(
            apiKey: apiKey,
            endpoint: URL(string: "https://example.invalid/v1")!,
            onConfigurationError: nil,
            terminatedUI: nil
        )
    }

    func testFailsClosedForProdKeysWithNoCache() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_abcdef1234567890"))
        XCTAssertFalse(store.canTriggerReport)
    }

    func testFailsOpenForDevAndStagingKeys() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234567890"))
        XCTAssertTrue(store.canTriggerReport)

        store.install(runtime: runtime(apiKey: "it_staging_abcdef1234567890"))
        XCTAssertTrue(store.canTriggerReport)
    }

    func testPrefersCachedConfigOverFailModeDefault() {
        let seeded = AttestationStore(defaults: defaults)
        seeded.adopt(requireTesterAttestation: false, apiKey: "it_abcdef1234567890")

        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_abcdef1234567890"))
        XCTAssertTrue(store.canTriggerReport)
    }

    func testIgnoresCachedConfigForDifferentKey() {
        let seeded = AttestationStore(defaults: defaults)
        seeded.adopt(requireTesterAttestation: false, apiKey: "it_otherkey")

        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_abcdef1234567890"))
        XCTAssertFalse(store.canTriggerReport)
    }

    func testAdoptedServerValueBeatsFailOpenDefault() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234567890"))
        XCTAssertTrue(store.canTriggerReport)
        store.adopt(requireTesterAttestation: true, apiKey: "it_dev_abcdef1234567890")
        XCTAssertFalse(store.canTriggerReport)
    }

    func testTokenUnlocksTestersOnlyMode() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_abcdef1234567890"))
        XCTAssertFalse(store.canTriggerReport)

        store.setTesterToken("itt_sometoken", expiresAt: nil)
        XCTAssertTrue(store.canTriggerReport)

        store.clearTesterToken()
        XCTAssertFalse(store.canTriggerReport)
    }

    func testExpiredTokenIsTreatedAsAbsent() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_abcdef1234567890"))
        store.setTesterToken("itt_sometoken", expiresAt: Date(timeIntervalSinceNow: -1))
        XCTAssertNil(store.testerToken)
        XCTAssertFalse(store.canTriggerReport)
    }

    func testFutureExpiryIsHonoured() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_abcdef1234567890"))
        store.setTesterToken("itt_sometoken", expiresAt: Date(timeIntervalSinceNow: 60))
        XCTAssertEqual(store.testerToken, "itt_sometoken")
    }

    func testFailModeDefaultPerPrefix() {
        XCTAssertTrue(AttestationStore.failModeDefault(for: "it_abc"))
        XCTAssertFalse(AttestationStore.failModeDefault(for: "it_dev_abc"))
        XCTAssertFalse(AttestationStore.failModeDefault(for: "it_staging_abc"))
    }
}
