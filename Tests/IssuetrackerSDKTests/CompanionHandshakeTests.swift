import XCTest
@testable import IssuetrackerSDK

/// The handshake's URL handling, which is the only place a value
/// chosen by another app on the device enters the SDK.
///
/// The network half (`redeemTesterClaim`) is not covered here: it has
/// no seam that does not also weaken the thing being tested, and its
/// server side is exercised by the callable's own contract. What is
/// covered is everything that decides whether a URL is ours, whether
/// it is the answer we asked for, and what the nonce is worth.
@MainActor
final class CompanionHandshakeTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        CompanionHandshake.install(callbackURLScheme: "com.example.app")
    }

    override func tearDown() async throws {
        CompanionHandshake.install(callbackURLScheme: nil)
        try await super.tearDown()
    }

    private func runtime() -> Runtime {
        Runtime(
            apiKey: "it_dev_abcdef1234",
            endpoint: URL(string: "https://example.invalid/v1")!,
            onConfigurationError: nil,
            terminatedUI: nil
        )
    }

    func testAForeignURLIsNotConsumed() {
        // The host app forwards EVERY url it is opened with, so a
        // false here is what lets its own deep links keep working.
        for foreign in [
            "com.example.app://some/other/place",
            "https://example.com/issuetracker-attest/v1?claim=x",
            "com.example.app://issuetracker-attest-lookalike/v1",
        ] {
            XCTAssertFalse(
                CompanionHandshake.handle(URL(string: foreign)!, runtime: runtime()),
                "consumed \(foreign)"
            )
        }
    }

    func testOurURLIsConsumedEvenWhenThereIsNothingToDoWithIt() {
        // No handshake in flight: the URL is still ours, and saying so
        // stops the host app hunting for another handler for a URL we
        // have already decided about.
        let url = URL(string: "com.example.app://issuetracker-attest/v1?nonce=abc&claim=itc_x")!
        XCTAssertTrue(CompanionHandshake.handle(url, runtime: runtime()))
    }

    func testAnEmptyPathIsAcceptedAndAWrongOneIsNot() {
        XCTAssertTrue(
            CompanionHandshake.handle(
                URL(string: "com.example.app://issuetracker-attest?nonce=a&claim=b")!,
                runtime: runtime()
            )
        )
        XCTAssertFalse(
            CompanionHandshake.handle(
                URL(string: "com.example.app://issuetracker-attest/v2?nonce=a&claim=b")!,
                runtime: runtime()
            )
        )
    }

    func testTheNonceHasTheShapeTheServerAndCompanionBothExpect() {
        // 16 random bytes, base64url without padding — 22 chars, and
        // comfortably inside TesterNonceSchema's 16...128 bounds.
        let nonce = CompanionHandshake.makeNonce()
        XCTAssertEqual(nonce?.count, 22)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        XCTAssertTrue(nonce?.unicodeScalars.allSatisfy(allowed.contains) == true)
        XCTAssertFalse(nonce?.contains("=") == true)

        // Two draws must not collide; a fixed nonce would make every
        // callback forgeable after the first observation.
        XCTAssertNotEqual(CompanionHandshake.makeNonce(), CompanionHandshake.makeNonce())
    }

    func testNonceComparisonIsExactAndLengthSafe() {
        let nonce = CompanionHandshake.makeNonce()!
        XCTAssertTrue(CompanionHandshake.constantTimeEquals(nonce, nonce))
        XCTAssertFalse(CompanionHandshake.constantTimeEquals(nonce, String(nonce.dropLast())))
        XCTAssertFalse(CompanionHandshake.constantTimeEquals(nonce, nonce + "x"))
        XCTAssertFalse(CompanionHandshake.constantTimeEquals("", nonce))
        XCTAssertTrue(CompanionHandshake.constantTimeEquals("", ""))
    }

    func testNoCallbackSchemeMeansTheHandshakeIsNeverOffered() {
        // A host that did not configure a callback scheme did not ask
        // for this, and has nowhere for the answer to arrive.
        CompanionHandshake.install(callbackURLScheme: nil)
        XCTAssertFalse(CompanionHandshake.canOffer(runtime: runtime()))
    }
}
