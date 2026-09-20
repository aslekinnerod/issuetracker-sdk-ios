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

    // MARK: - apiKey binding (ADR-0005 Decision 9)

    func testATokenSetBeforeConfigureIsAdoptedByTheFirstConfigure() {
        // `setTesterToken` is explicitly documented as safe to call
        // before `configure()`, so the unbound write is a supported
        // state and not a bug to defend against.
        let store = AttestationStore(defaults: defaults)
        store.setTesterToken("itt_injected", expiresAt: nil)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234"))
        store.adopt(requireTesterAttestation: true, apiKey: "it_dev_abcdef1234")
        XCTAssertEqual(store.testerToken, "itt_injected")
        XCTAssertTrue(store.canTriggerReport)
    }

    func testATokenBoundToAnotherKeyIsClearedRatherThanCarriedForward() {
        // The symptom this prevents is nasty precisely because it is
        // quiet: the tester's gestures keep working against the new
        // project while every report they file is rejected at ingest.
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_first00000"))
        store.setTesterToken("itt_first", expiresAt: nil)
        XCTAssertEqual(store.testerToken, "itt_first")

        store.install(runtime: runtime(apiKey: "it_dev_second0000"))
        XCTAssertNil(store.testerToken)
    }

    func testReconfiguringWithTheSameKeyKeepsTheToken() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234"))
        store.setTesterToken("itt_same", expiresAt: nil)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234"))
        XCTAssertEqual(store.testerToken, "itt_same")
    }

    // MARK: - The unified expiry rule (ADR-0005 Decision 10)

    func testZeroAndNegativeExpiriesMeanNoLocalExpiry() {
        // iOS used to read a stored 0 as Date(1970) — therefore
        // expired — which is the opposite of what Android and web
        // have always done with the same value. One rule, four
        // stores: absent or <= 0 means no local expiry.
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234"))

        store.setTesterToken("itt_zero", expiresAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(store.testerToken, "itt_zero")

        store.setTesterToken("itt_negative", expiresAt: Date(timeIntervalSince1970: -5))
        XCTAssertEqual(store.testerToken, "itt_negative")
    }

    func testAnExpiredTokenIsNotJustHiddenButCleared() {
        // Self-healing: without the clear, a dead token sits on disk
        // forever and keeps being attached to reports that keep being
        // rejected — and renew-on-use only ever fires on a token the
        // server still accepts, so nothing else would remove it.
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234"))
        store.setTesterToken("itt_stale", expiresAt: Date(timeIntervalSinceNow: -1))

        XCTAssertNil(store.testerToken)
        XCTAssertNil(defaults.string(forKey: "io.issuetracker.sdk.testerToken"))
        XCTAssertNil(defaults.object(forKey: "io.issuetracker.sdk.testerTokenExpiresAt"))
        XCTAssertNil(defaults.string(forKey: "io.issuetracker.sdk.testerTokenApiKey"))
    }

    // MARK: - Renew-on-use

    func testTheServerExtendedExpiryIsAdoptedButOnlyForwards() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234"))
        let soon = Date(timeIntervalSinceNow: 60)
        store.setTesterToken("itt_live", expiresAt: soon)

        let later = Date(timeIntervalSinceNow: 3600).timeIntervalSince1970
        store.adoptRenewedExpiry(millisecondsSince1970: later * 1000)
        XCTAssertEqual(defaults.double(forKey: "io.issuetracker.sdk.testerTokenExpiresAt"), later, accuracy: 0.001)

        // A response that arrives out of order must not shorten a life
        // the server already extended.
        store.adoptRenewedExpiry(millisecondsSince1970: soon.timeIntervalSince1970 * 1000)
        XCTAssertEqual(defaults.double(forKey: "io.issuetracker.sdk.testerTokenExpiresAt"), later, accuracy: 0.001)
    }

    func testARenewalForATokenThatIsGoneDoesNotResurrectTheSlot() {
        // A submit response can land after a reconfigure or a clear.
        // Writing an expiry for a token that no longer exists would
        // leave an orphan key that the next token silently inherits.
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234"))
        store.adoptRenewedExpiry(millisecondsSince1970: Date(timeIntervalSinceNow: 3600).timeIntervalSince1970 * 1000)
        XCTAssertNil(defaults.object(forKey: "io.issuetracker.sdk.testerTokenExpiresAt"))
    }

    func testFailModeDefaultPerPrefix() {
        XCTAssertTrue(AttestationStore.failModeDefault(for: "it_abc"))
        XCTAssertFalse(AttestationStore.failModeDefault(for: "it_dev_abc"))
        XCTAssertFalse(AttestationStore.failModeDefault(for: "it_staging_abc"))
    }
}
