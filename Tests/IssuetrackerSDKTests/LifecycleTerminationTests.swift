import XCTest
import UIKit
@testable import IssuetrackerSDK

/// ADR-0003 Decision 9, end to end: server says the bound project is
/// gone → the SDK terminates, stays terminated across a restart, stops
/// talking to the server, purges its queue, and tears its triggers
/// down.
///
/// `LifecycleStoreTests` drives the state machine directly.
/// `SdkErrorWireContractTests` drives the parse. This suite is the one
/// the ADR's implementation status calls deferred: it starts from
/// stubbed callable *responses* and asserts on the resulting SDK
/// state, so it fails if any link in parse → dispatch → persist →
/// callback → teardown breaks.
///
/// The dispatch sites all read `LifecycleStore.shared`, so each test
/// swaps in a store backed by a throwaway `UserDefaults` suite and
/// restores the real one afterwards.
@MainActor
final class LifecycleTerminationTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: LifecycleStore!
    private var previousShared: LifecycleStore!
    private var attestation: AttestationStore!

    private let configFunction = "getSdkConfig"
    private let reportFunction = "createIssueFromSdk"

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "io.issuetracker.sdk.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = LifecycleStore(defaults: defaults)
        previousShared = LifecycleStore._swapSharedForTesting(store)
        // Own UserDefaults suite too, so the config cache never touches
        // the host's standard defaults.
        attestation = AttestationStore(defaults: defaults)
        CallableStub.start()
    }

    override func tearDown() async throws {
        CallableStub.stop()
        LifecycleStore._swapSharedForTesting(previousShared)
        previousShared = nil
        store = nil
        attestation = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func runtime(
        apiKey: String = "it_dev_stub",
        onConfigurationError: ((SdkErrorReason) -> Void)? = nil
    ) -> Runtime {
        Runtime(
            apiKey: apiKey,
            endpoint: Runtime.resolveEndpoint(for: apiKey),
            onConfigurationError: onConfigurationError,
            terminatedUI: nil
        )
    }

    // MARK: - Every non-recoverable reason terminates

    func testEveryNonRecoverableReasonTerminatesTheSdk() async {
        // Rebuilt per case so each reason gets a virgin lifecycle —
        // TERMINATED is one-way, so a shared store would make every
        // case after the first vacuously true.
        let cases: [(error: String, status: Int, reason: SdkErrorReason)] = [
            ("project_deleted", 404, .projectDeleted),
            ("project_not_found", 404, .projectNotFound),
            ("api_key_revoked", 403, .apiKeyRevoked),
            ("workspace_suspended", 403, .workspaceSuspended),
            ("invalid_api_key", 401, .invalidApiKey),
        ]

        for row in cases {
            let scratch = UserDefaults(suiteName: "\(suiteName!).\(row.error)")!
            defer { scratch.removePersistentDomain(forName: "\(suiteName!).\(row.error)") }
            let freshStore = LifecycleStore(defaults: scratch)
            LifecycleStore._swapSharedForTesting(freshStore)

            var reported: [SdkErrorReason] = []
            CallableStub.enqueueError(
                function: configFunction,
                status: row.status,
                error: row.error,
                recoverable: false
            )
            await AttestationStore(defaults: scratch).refreshRemoteConfig(
                runtime: runtime(onConfigurationError: { reported.append($0) })
            )

            XCTAssertTrue(freshStore.isTerminated, "\(row.error) must terminate the SDK")
            XCTAssertEqual(reported, [row.reason], "onConfigurationError payload for \(row.error)")
            XCTAssertEqual(
                scratch.string(forKey: "io.issuetracker.sdk.terminatedReason"),
                row.error,
                "\(row.error) must be persisted under its wire value"
            )
        }
    }

    // MARK: - Recoverable reasons must NOT terminate

    func testQuotaExceededDoesNotTerminate() async {
        var reported: [SdkErrorReason] = []
        CallableStub.enqueueError(
            function: configFunction,
            status: 429,
            error: "quota_exceeded",
            recoverable: true,
            retryAfterSeconds: 30
        )
        await attestation.refreshRemoteConfig(
            runtime: runtime(onConfigurationError: { reported.append($0) })
        )

        XCTAssertFalse(store.isTerminated, "quota_exceeded is recoverable — the SDK must stay alive")
        XCTAssertEqual(reported, [])
        XCTAssertNil(defaults.string(forKey: "io.issuetracker.sdk.terminatedReason"))
    }

    func testTransientDoesNotTerminate() async {
        CallableStub.enqueueError(
            function: configFunction,
            status: 503,
            error: "transient",
            recoverable: true
        )
        await attestation.refreshRemoteConfig(runtime: runtime())
        XCTAssertFalse(store.isTerminated)
    }

    func testTesterGatingRejectionDoesNotTerminate() async {
        // ADR-0005: non-recoverable, but the project is alive and the
        // key is valid — only this install lacks attestation.
        for error in ["tester_attestation_required", "tester_token_invalid"] {
            CallableStub.enqueueError(
                function: configFunction,
                status: 403,
                error: error,
                recoverable: false
            )
            await attestation.refreshRemoteConfig(runtime: runtime())
            XCTAssertFalse(store.isTerminated, "\(error) must not be terminal")
        }
    }

    func testOfflineDoesNotTerminate() async {
        // Nothing scripted → the stub fails the connection. A device in
        // a tunnel must never be mistaken for a deleted project.
        await attestation.refreshRemoteConfig(runtime: runtime())
        XCTAssertFalse(store.isTerminated)
    }

    func testBare404WithoutDetailsDoesNotTerminate() async {
        CallableStub.enqueueError(
            function: configFunction,
            status: 404,
            error: nil,
            recoverable: nil,
            includeDetails: false
        )
        await attestation.refreshRemoteConfig(runtime: runtime())
        XCTAssertFalse(
            store.isTerminated,
            "a 404 with no details object is not the Decision 9 signal"
        )
    }

    // MARK: - TERMINATED survives a restart

    func testTerminatedSurvivesSimulatedProcessRestart() async {
        CallableStub.enqueueError(
            function: configFunction,
            status: 404,
            error: "project_deleted",
            recoverable: false,
            deletedAt: 1_747_000_000_000
        )
        await attestation.refreshRemoteConfig(runtime: runtime())
        XCTAssertTrue(store.isTerminated)

        // Cold start: a brand-new store over the same on-disk defaults,
        // exactly what `LifecycleStore.shared`'s lazy init does on the
        // next app launch.
        let afterRelaunch = LifecycleStore(defaults: defaults)
        XCTAssertTrue(afterRelaunch.isTerminated, "TERMINATED must survive a process restart")
        guard case .terminated(let reason, _) = afterRelaunch.state else {
            return XCTFail("expected .terminated after relaunch")
        }
        XCTAssertEqual(reason, .projectDeleted, "the causing reason must survive too")
    }

    func testTerminatedSurvivesManyRestarts() async {
        CallableStub.enqueueError(
            function: configFunction,
            status: 403,
            error: "api_key_revoked",
            recoverable: false
        )
        await attestation.refreshRemoteConfig(runtime: runtime())

        for launch in 1...5 {
            let store = LifecycleStore(defaults: defaults)
            XCTAssertTrue(store.isTerminated, "still terminated on launch \(launch)")
        }
    }

    // MARK: - TERMINATED is one-way

    func testLaterSuccessfulCallDoesNotResurrect() async {
        CallableStub.enqueueError(
            function: configFunction,
            status: 404,
            error: "project_deleted",
            recoverable: false
        )
        await attestation.refreshRemoteConfig(runtime: runtime())
        XCTAssertTrue(store.isTerminated)

        // Project restored on the server within the tombstone window —
        // the ADR is explicit that deployed SDKs do NOT come back.
        CallableStub.enqueueSuccess(
            function: configFunction,
            result: ["requireTesterAttestation": false]
        )
        await attestation.refreshRemoteConfig(runtime: runtime())
        XCTAssertTrue(store.isTerminated, "a 200 must not un-terminate the SDK")

        let afterRelaunch = LifecycleStore(defaults: defaults)
        XCTAssertTrue(afterRelaunch.isTerminated)
    }

    func testReconfigureDoesNotResurrect() async {
        CallableStub.enqueueError(
            function: configFunction,
            status: 403,
            error: "workspace_suspended",
            recoverable: false
        )
        await attestation.refreshRemoteConfig(runtime: runtime())
        XCTAssertTrue(store.isTerminated)

        // A second configure() builds a fresh Runtime; the lifecycle is
        // process-wide and must ignore it. (Recovery, per the ADR, is
        // deliberately not offered — see the audit finding about the
        // configure() doc comment that claims otherwise.)
        let second = runtime()
        attestation.install(runtime: second)
        CallableStub.enqueueSuccess(
            function: configFunction,
            result: ["requireTesterAttestation": false]
        )
        await attestation.refreshRemoteConfig(runtime: second)
        XCTAssertTrue(store.isTerminated, "re-configure() must not clear TERMINATED")
    }

    func testApiKeyChangeDoesNotResurrect() async {
        CallableStub.enqueueError(
            function: configFunction,
            status: 401,
            error: "invalid_api_key",
            recoverable: false
        )
        await attestation.refreshRemoteConfig(runtime: runtime(apiKey: "it_dev_first"))
        XCTAssertTrue(store.isTerminated)

        // Host swaps in a completely different key (different project).
        CallableStub.enqueueSuccess(
            function: configFunction,
            result: ["requireTesterAttestation": false]
        )
        await attestation.refreshRemoteConfig(runtime: runtime(apiKey: "it_dev_second"))
        XCTAssertTrue(store.isTerminated, "TERMINATED is install-wide and one-way")
    }

    func testClockChangeDoesNotResurrect() {
        // The persisted `terminatedAt` is a diagnostic, never an
        // expiry. A device whose clock jumps backwards (or forwards
        // past any plausible TTL) must stay terminated.
        for stamp in [0.0, -1.0, 1.0, 4_102_444_800.0, Date.distantFuture.timeIntervalSince1970] {
            defaults.set("project_deleted", forKey: "io.issuetracker.sdk.terminatedReason")
            defaults.set(stamp, forKey: "io.issuetracker.sdk.terminatedAt")
            let store = LifecycleStore(defaults: defaults)
            XCTAssertTrue(store.isTerminated, "terminatedAt=\(stamp) must not resurrect the SDK")
        }
    }

    func testCallbackFiresOnceAcrossRepeatedTerminalResponses() async {
        var reported: [SdkErrorReason] = []
        let rt = runtime(onConfigurationError: { reported.append($0) })

        for _ in 0..<3 {
            CallableStub.enqueueError(
                function: configFunction,
                status: 404,
                error: "project_deleted",
                recoverable: false
            )
            await attestation.refreshRemoteConfig(runtime: rt)
        }

        XCTAssertEqual(reported, [.projectDeleted], "onConfigurationError is a one-shot")
    }

    // MARK: - Triggers are torn down

    /// Both SDK-owned trigger surfaces that can be removed without
    /// leaving the tester stranded — the ADR-0008 floating button
    /// (`FloatingReportButton`) and the VoiceOver custom action
    /// (`AccessibilityActionObserver`) — tear themselves down off this
    /// notification. It is the only teardown signal, so it has to fire
    /// exactly once, on the transition, from the dispatch path.
    func testTerminationPostsTheTriggerTeardownNotificationExactlyOnce() async {
        // `queue: nil` so the block runs synchronously on the posting
        // thread — an OperationQueue hop would race the assertion.
        let posts = Counter()
        let token = NotificationCenter.default.addObserver(
            forName: LifecycleStore.terminatedNotification,
            object: nil,
            queue: nil
        ) { _ in posts.value += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        for _ in 0..<2 {
            CallableStub.enqueueError(
                function: configFunction,
                status: 403,
                error: "api_key_revoked",
                recoverable: false
            )
            await attestation.refreshRemoteConfig(runtime: runtime())
        }

        XCTAssertEqual(posts.value, 1)
    }

    func testRecoverableErrorDoesNotPostTeardownNotification() async {
        let posts = Counter()
        let token = NotificationCenter.default.addObserver(
            forName: LifecycleStore.terminatedNotification,
            object: nil,
            queue: nil
        ) { _ in posts.value += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        CallableStub.enqueueError(
            function: configFunction,
            status: 429,
            error: "quota_exceeded",
            recoverable: true
        )
        await attestation.refreshRemoteConfig(runtime: runtime())

        XCTAssertEqual(posts.value, 0)
    }

    /// The floating button and the VoiceOver action are gated on
    /// `LifecycleStore.shared.isTerminated` at reconcile time, so a
    /// process that starts up already terminated never installs them —
    /// not just the live-teardown case.
    func testTriggerSurfacesSeeTerminatedStateFromColdStart() {
        defaults.set("project_deleted", forKey: "io.issuetracker.sdk.terminatedReason")
        defaults.set(Date().timeIntervalSince1970, forKey: "io.issuetracker.sdk.terminatedAt")
        let coldStore = LifecycleStore(defaults: defaults)
        LifecycleStore._swapSharedForTesting(coldStore)

        XCTAssertTrue(
            LifecycleStore.shared.isTerminated,
            "the gate both trigger surfaces read must be true before any network call"
        )
        // Reconciling with the SDK terminated must not throw or attach
        // anything; without a scene there is no window to inspect, so
        // this is a smoke check of the teardown path only.
        FloatingReportButton.shared.setEnabled(true)
        AccessibilityActionObserver.setEnabled(true)
        FloatingReportButton.shared.setEnabled(false)
        AccessibilityActionObserver.setEnabled(false)
    }

    /// The terminal UI itself. Presenting it needs a window scene,
    /// which a SwiftPM test bundle does not have — so this skips in CI
    /// and runs only under an app-hosted scheme.
    func testTriggerInTerminatedStateShowsTheTerminalSurface() throws {
        try XCTSkipIf(
            UIApplication.shared.connectedScenes.isEmpty,
            "needs a UI test host: SwiftPM test bundles run without a UIScene"
        )
        defaults.set("project_deleted", forKey: "io.issuetracker.sdk.terminatedReason")
        defaults.set(Date().timeIntervalSince1970, forKey: "io.issuetracker.sdk.terminatedAt")
        LifecycleStore._swapSharedForTesting(LifecycleStore(defaults: defaults))

        ReportingSession.present(runtime: runtime())
        XCTAssertTrue(ReportingSession.isPresented)
    }

    // MARK: - Queue purge

    /// ADR-0003 Decision 9 §6: "Drop the queue atomically on first
    /// TERMINATED signal — and persist a `terminatedAt` marker so a
    /// process restart does not re-attempt delivery."
    ///
    /// `PendingCrashStore` is the SDK's only on-disk queue of
    /// undelivered reports (crash markers awaiting MetricKit
    /// confirmation, retained for 7 days). Both halves are now
    /// implemented in `transitionToTerminated`: persist the marker,
    /// then drop the queue.
    func testTerminationPurgesThePendingReportQueue() async {
        let sessionId = "test-\(UUID().uuidString)"
        addTeardownBlock { PendingCrashStore.shared.remove(sessionId: sessionId) }
        PendingCrashStore.shared.add(PendingCrashMarker(
            sessionId: sessionId,
            startedAt: Date(),
            endedAt: Date(),
            appVersion: "1.0",
            osVersion: "18.0",
            lastLifecycleState: .active,
            breadcrumbs: []
        ))
        XCTAssertTrue(
            PendingCrashStore.shared.list().contains { $0.sessionId == sessionId },
            "precondition: the marker is queued on disk"
        )

        CallableStub.enqueueError(
            function: configFunction,
            status: 404,
            error: "project_deleted",
            recoverable: false
        )
        await attestation.refreshRemoteConfig(runtime: runtime())
        XCTAssertTrue(store.isTerminated)

        XCTAssertFalse(
            PendingCrashStore.shared.list().contains { $0.sessionId == sessionId },
            "the local queue must be purged on the first TERMINATED signal"
        )
        XCTAssertEqual(
            PendingCrashStore.shared.list().count, 0,
            "the drop is atomic — the whole queue goes, not just matching entries"
        )
    }

    /// The purge is worthless if the next `configure()` refills the
    /// queue. `CrashReporter.reportCrashIfAny` is what promotes the
    /// previous session's marker into `PendingCrashStore`, and it runs
    /// on every launch — so it has to honour the lifecycle too.
    func testTerminatedSdkDoesNotRepopulateTheQueueOnNextLaunch() {
        defaults.set("project_deleted", forKey: "io.issuetracker.sdk.terminatedReason")
        defaults.set(Date().timeIntervalSince1970, forKey: "io.issuetracker.sdk.terminatedAt")
        LifecycleStore._swapSharedForTesting(LifecycleStore(defaults: defaults))

        let sessionId = "test-\(UUID().uuidString)"
        addTeardownBlock { PendingCrashStore.shared.remove(sessionId: sessionId) }
        PendingCrashStore.shared.add(PendingCrashMarker(
            sessionId: sessionId,
            startedAt: Date(),
            endedAt: Date(),
            appVersion: "1.0",
            osVersion: "18.0",
            lastLifecycleState: .active,
            breadcrumbs: []
        ))

        CrashReporter.reportCrashIfAny()

        XCTAssertEqual(
            PendingCrashStore.shared.list().count, 0,
            "a terminated install must re-purge on launch, never repopulate"
        )
    }

    /// Guard against over-correcting: a healthy SDK still tracks
    /// sessions and still queues an unfinished one for MetricKit.
    func testHealthySdkStillTracksCrashesOnLaunch() {
        XCTAssertFalse(LifecycleStore.shared.isTerminated, "precondition: OK state")
        let before = PendingCrashStore.shared.list().count
        CrashReporter.reportCrashIfAny()
        XCTAssertGreaterThanOrEqual(
            PendingCrashStore.shared.list().count, before,
            "an OK SDK must not have its crash pipeline gated off"
        )
    }

    // MARK: - The SDK stops talking to the server

    /// A terminated SDK must not call the report endpoint again. The
    /// crash-report path is a background task, so it carries its own
    /// pre-flight gate — the twin of `ReportingSession.present`'s.
    func testTerminatedSdkDoesNotUploadCrashReports() async {
        defaults.set("project_deleted", forKey: "io.issuetracker.sdk.terminatedReason")
        defaults.set(Date().timeIntervalSince1970, forKey: "io.issuetracker.sdk.terminatedAt")
        LifecycleStore._swapSharedForTesting(LifecycleStore(defaults: defaults))
        XCTAssertTrue(LifecycleStore.shared.isTerminated)

        CallableStub.enqueueSuccess(function: reportFunction, result: ["issueId": "abc"])
        await CrashReporter.sendConfirmedCrash(
            runtime: runtime(),
            marker: PendingCrashMarker(
                sessionId: UUID().uuidString,
                startedAt: Date(),
                endedAt: Date(),
                appVersion: "1.0",
                osVersion: "18.0",
                lastLifecycleState: .active,
                breadcrumbs: []
            ),
            cause: .appExit(reason: "watchdog")
        )

        XCTAssertEqual(
            CallableStub.requestCount(for: reportFunction), 0,
            "a terminated SDK must not call the report endpoint"
        )
        XCTAssertEqual(
            CallableStub.totalRequestCount, 0,
            "and must not call anything else either"
        )
    }

    /// The other half of ITD-164's config finding: `configure()` fires
    /// `getSdkConfig` on every launch, so an ungated refresh is what
    /// turns one deleted project into forever-traffic from the whole
    /// deployed cohort.
    func testTerminatedSdkDoesNotFetchRemoteConfig() async {
        defaults.set("project_deleted", forKey: "io.issuetracker.sdk.terminatedReason")
        defaults.set(Date().timeIntervalSince1970, forKey: "io.issuetracker.sdk.terminatedAt")
        LifecycleStore._swapSharedForTesting(LifecycleStore(defaults: defaults))

        // Five launches of a terminated install.
        for _ in 0..<5 {
            CallableStub.enqueueSuccess(
                function: configFunction,
                result: ["requireTesterAttestation": false]
            )
            await attestation.refreshRemoteConfig(runtime: runtime())
        }

        XCTAssertEqual(
            CallableStub.requestCount(for: configFunction), 0,
            "a terminated install must stop fetching config, on every launch forever"
        )
    }

    // MARK: - …but a healthy SDK keeps working

    /// The gates are on TERMINATED, not on everything. If these break,
    /// the SDK is silently dead for every healthy integrator.
    func testHealthySdkStillFetchesRemoteConfigAndAdoptsIt() async {
        CallableStub.enqueueSuccess(
            function: configFunction,
            result: ["requireTesterAttestation": true]
        )
        attestation.install(runtime: runtime(apiKey: "it_dev_stub"))
        await attestation.refreshRemoteConfig(runtime: runtime())

        XCTAssertEqual(CallableStub.requestCount(for: configFunction), 1)
        XCTAssertFalse(
            attestation.canTriggerReport,
            "the fetched requireTesterAttestation=true must have been adopted"
        )
    }

    func testHealthySdkStillUploadsCrashReports() async {
        XCTAssertFalse(store.isTerminated, "precondition: OK state")
        CallableStub.enqueueSuccess(function: reportFunction, result: ["issueId": "abc"])
        await CrashReporter.sendConfirmedCrash(
            runtime: runtime(),
            marker: PendingCrashMarker(
                sessionId: UUID().uuidString,
                startedAt: Date(),
                endedAt: Date(),
                appVersion: "1.0",
                osVersion: "18.0",
                lastLifecycleState: .active,
                breadcrumbs: []
            ),
            cause: .appExit(reason: "watchdog")
        )

        XCTAssertEqual(CallableStub.requestCount(for: reportFunction), 1)
        XCTAssertFalse(store.isTerminated, "a 200 must not terminate anything")
    }

    /// A recoverable failure on the background crash path must leave
    /// the SDK alive — the crash-path dispatch added for ITD-164 must
    /// not become a hair-trigger.
    func testRecoverableErrorOnCrashUploadDoesNotTerminate() async {
        for (status, error) in [(429, "quota_exceeded"), (503, "transient")] {
            CallableStub.enqueueError(
                function: reportFunction,
                status: status,
                error: error,
                recoverable: true
            )
            await CrashReporter.sendConfirmedCrash(
                runtime: runtime(),
                marker: PendingCrashMarker(
                    sessionId: UUID().uuidString,
                    startedAt: Date(),
                    endedAt: Date(),
                    appVersion: "1.0",
                    osVersion: "18.0",
                    lastLifecycleState: .active,
                    breadcrumbs: []
                ),
                cause: .appExit(reason: "watchdog")
            )
            XCTAssertFalse(store.isTerminated, "\(error) on the crash path is recoverable")
        }
    }

    /// And the same path must itself honour the contract: a terminal
    /// `details.error` arriving on a background crash upload is as
    /// authoritative as one arriving on a user-initiated submit.
    func testTerminalErrorOnCrashUploadTerminatesTheSdk() async {
        CallableStub.enqueueError(
            function: reportFunction,
            status: 403,
            error: "api_key_revoked",
            recoverable: false
        )
        await CrashReporter.sendConfirmedCrash(
            runtime: runtime(),
            marker: PendingCrashMarker(
                sessionId: UUID().uuidString,
                startedAt: Date(),
                endedAt: Date(),
                appVersion: "1.0",
                osVersion: "18.0",
                lastLifecycleState: .active,
                breadcrumbs: []
            ),
            cause: .appExit(reason: "watchdog")
        )
        XCTAssertEqual(CallableStub.requestCount(for: reportFunction), 1, "precondition: it called")

        XCTAssertTrue(
            store.isTerminated,
            "api_key_revoked on the crash-upload path must terminate the SDK"
        )
        guard case .terminated(let reason, _) = store.state else {
            return XCTFail("expected .terminated")
        }
        XCTAssertEqual(reason, .apiKeyRevoked, "the crash path must report the wire reason")
    }

    // MARK: - ITD-163: one termination predicate per platform

    /// Every dispatch site on this platform reads the same predicate,
    /// `SdkErrorReason.isTerminal`. This pins that they agree — drive
    /// the config path and the background crash path with the identical
    /// reason and assert both reach the identical lifecycle.
    ///
    /// The reason this is a test and not a code-reading exercise:
    /// `recoverable` and `isTerminal` are NOT interchangeable. ADR-0005's
    /// tester-gating reasons are `recoverable: false` but deliberately
    /// non-terminal, so a path that dispatched on `!recoverable` would
    /// permanently kill an install the other paths keep alive. Those two
    /// reasons are what make this matrix bite.
    func testConfigAndCrashPathsShareOneTerminationPredicate() async {
        for reason in SdkErrorReason.allCases {
            let expected = reason.isTerminal

            let configTerminated = await drive(reason: reason, via: configFunction) { rt, att in
                await att.refreshRemoteConfig(runtime: rt)
            }
            let crashTerminated = await drive(reason: reason, via: reportFunction) { rt, _ in
                await CrashReporter.sendConfirmedCrash(
                    runtime: rt,
                    marker: PendingCrashMarker(
                        sessionId: UUID().uuidString,
                        startedAt: Date(),
                        endedAt: Date(),
                        appVersion: "1.0",
                        osVersion: "18.0",
                        lastLifecycleState: .active,
                        breadcrumbs: []
                    ),
                    cause: .appExit(reason: "watchdog")
                )
            }

            XCTAssertEqual(
                configTerminated, expected,
                "config path disagrees with isTerminal for \(reason.rawValue)"
            )
            XCTAssertEqual(
                crashTerminated, expected,
                "crash path disagrees with isTerminal for \(reason.rawValue)"
            )
            XCTAssertEqual(
                configTerminated, crashTerminated,
                "the two dispatch paths must agree on \(reason.rawValue)"
            )
        }
    }

    /// Guards the predicate itself: `isTerminal` must not be an alias
    /// for `!isRecoverable`. If someone ever collapses the two, this
    /// fails before the matrix above gets a chance to.
    func testTerminalIsNotAnAliasForNonRecoverable() {
        let divergent = SdkErrorReason.allCases.filter { !$0.isRecoverable && !$0.isTerminal }
        XCTAssertEqual(
            Set(divergent.map(\.rawValue)),
            ["tester_attestation_required", "tester_token_invalid"],
            "non-recoverable-but-not-terminal is a real category — see ADR-0005"
        )
    }

    /// Runs one dispatch path against a virgin lifecycle store and
    /// reports whether it terminated. Each call gets its own
    /// `UserDefaults` suite because TERMINATED is one-way — a shared
    /// store would make every case after the first vacuously true.
    private func drive(
        reason: SdkErrorReason,
        via function: String,
        _ body: (Runtime, AttestationStore) async -> Void
    ) async -> Bool {
        let name = "\(suiteName!).\(function).\(reason.rawValue)"
        let scratch = UserDefaults(suiteName: name)!
        defer { scratch.removePersistentDomain(forName: name) }
        let fresh = LifecycleStore(defaults: scratch)
        LifecycleStore._swapSharedForTesting(fresh)

        CallableStub.enqueueError(
            function: function,
            // Status deliberately mismatched with the reason: the
            // contract says dispatch on details.error, never the status.
            status: 418,
            error: reason.rawValue,
            recoverable: reason.isRecoverable
        )
        await body(runtime(), AttestationStore(defaults: scratch))
        return fresh.isTerminated
    }
}
