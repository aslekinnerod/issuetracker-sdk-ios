import XCTest
@testable import IssuetrackerSDK

final class ProgressBarSnapshotTests: XCTestCase {
    private struct Vector: Decodable {
        let id: String
        let state: VectorState
        let expect: VectorExpect
        let variantOverrides: [String: VectorExpect]?
    }

    private struct VectorState: Decodable {
        let progress: Double?
        let phase: String
        let error: String?
        let issueId: String?
    }

    private struct VectorExpect: Decodable {
        let fillWidthPercent: Double?
        let badgeText: String?
        let statusContains: String?
        let statusEquals: String?
        let tintIsError: Bool?
        let indeterminateActive: Bool?
        let deterministicFillVisible: Bool?
        let iconWobbles: Bool?
        let fillIsAnimating: Bool?
        let statusTruncates: Bool?

        func merging(_ override: VectorExpect?) -> VectorExpect {
            guard let o = override else { return self }
            return VectorExpect(
                fillWidthPercent:         o.fillWidthPercent         ?? fillWidthPercent,
                badgeText:                o.badgeText                ?? badgeText,
                statusContains:           o.statusContains           ?? statusContains,
                statusEquals:             o.statusEquals             ?? statusEquals,
                tintIsError:              o.tintIsError              ?? tintIsError,
                indeterminateActive:      o.indeterminateActive      ?? indeterminateActive,
                deterministicFillVisible: o.deterministicFillVisible ?? deterministicFillVisible,
                iconWobbles:              o.iconWobbles              ?? iconWobbles,
                fillIsAnimating:          o.fillIsAnimating          ?? fillIsAnimating,
                statusTruncates:          o.statusTruncates          ?? statusTruncates
            )
        }
    }

    private struct VectorFile: Decodable {
        let cases: [Vector]
    }

    private func loadVectors() throws -> [Vector] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "test-vectors", withExtension: "json"),
            "test-vectors.json missing from test resources"
        )
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(VectorFile.self, from: data)
        return file.cases
    }

    private func phase(from raw: String) throws -> IssueProgressPhase {
        try XCTUnwrap(IssueProgressPhase(rawValue: raw), "unknown phase: \(raw)")
    }

    private func state(from v: VectorState) throws -> IssueProgressState {
        IssueProgressState(
            progress: v.progress ?? 0,
            phase: try phase(from: v.phase),
            error: v.error,
            issueId: v.issueId
        )
    }

    private func variants() -> [(ProgressVariant, IssueProgressCopy, String)] {
        [
            (.bug,   .bugDefault,   "bug"),
            (.task,  .taskDefault,  "task"),
            (.story, .storyDefault, "story"),
        ]
    }

    func testEveryVectorAcrossEveryVariant() throws {
        let vectors = try loadVectors()
        XCTAssertFalse(vectors.isEmpty, "no vectors loaded")

        for vector in vectors {
            let state = try state(from: vector.state)

            for (variant, copy, key) in variants() {
                let expect = vector.expect.merging(vector.variantOverrides?[key])
                let pres = ProgressPresentation.make(variant: variant, state: state, copy: copy)
                let label = "[\(vector.id) / \(variant)]"

                if let expected = expect.fillWidthPercent {
                    XCTAssertEqual(pres.fillWidthPercent, expected, accuracy: 0.001, "\(label) fillWidthPercent")
                }
                if let expected = expect.badgeText {
                    XCTAssertEqual(pres.badgeText, expected, "\(label) badgeText")
                }
                if let expected = expect.statusContains {
                    XCTAssertTrue(
                        pres.statusText.contains(expected),
                        "\(label) statusText '\(pres.statusText)' should contain '\(expected)'"
                    )
                }
                if let expected = expect.statusEquals {
                    XCTAssertEqual(pres.statusText, expected, "\(label) statusText equality")
                }
                if let expected = expect.tintIsError {
                    XCTAssertEqual(pres.tintIsError, expected, "\(label) tintIsError")
                }
                if let expected = expect.indeterminateActive {
                    XCTAssertEqual(pres.indeterminateActive, expected, "\(label) indeterminateActive")
                }
                if let expected = expect.deterministicFillVisible {
                    XCTAssertEqual(pres.deterministicFillVisible, expected, "\(label) deterministicFillVisible")
                }
                if let expected = expect.iconWobbles {
                    XCTAssertEqual(pres.iconWobbles, expected, "\(label) iconWobbles")
                }
                if let expected = expect.fillIsAnimating {
                    XCTAssertEqual(pres.fillIsAnimating, expected, "\(label) fillIsAnimating")
                }
                if expect.statusTruncates == true {
                    XCTAssertGreaterThan(
                        pres.statusText.count, 60,
                        "\(label) status should be long enough to truncate; lineLimit(1) handles render-time clip"
                    )
                }
            }
        }
    }

    func testHappyPathFillNeverGoesBackwards() throws {
        let copy = IssueProgressCopy.bugDefault
        let progressions: [Double] = [0, 0.1, 0.5, 1.0, 1.0, 1.0]
        let phases: [IssueProgressPhase] = [.idle, .uploading, .uploading, .uploading, .processing, .done]

        var lastDeterministicWidth: Double = 0
        for (i, phase) in phases.enumerated() {
            let state = IssueProgressState(progress: progressions[i], phase: phase, issueId: phase == .done ? "BUG-1" : nil)
            let pres = ProgressPresentation.make(variant: .bug, state: state, copy: copy)
            if pres.deterministicFillVisible {
                XCTAssertGreaterThanOrEqual(pres.fillWidthPercent, lastDeterministicWidth)
                lastDeterministicWidth = pres.fillWidthPercent
            }
        }
    }

    func testStallFreezesFillAtLastProgress() {
        let copy = IssueProgressCopy.bugDefault
        let stalled = IssueProgressState(progress: 0.4, phase: .stalled)
        let pres = ProgressPresentation.make(variant: .bug, state: stalled, copy: copy)
        XCTAssertEqual(pres.fillWidthPercent, 40, accuracy: 0.001)
        XCTAssertFalse(pres.fillIsAnimating)
        XCTAssertFalse(pres.iconWobbles)
        XCTAssertEqual(pres.statusText, copy.stalled)
    }

    func testErrorKeepsBarAtLastProgress() {
        let copy = IssueProgressCopy.taskDefault
        let errored = IssueProgressState(progress: 0.6, phase: .error, error: "Network connection lost")
        let pres = ProgressPresentation.make(variant: .task, state: errored, copy: copy)
        XCTAssertEqual(pres.fillWidthPercent, 60, accuracy: 0.001)
        XCTAssertTrue(pres.tintIsError)
        XCTAssertEqual(pres.statusText, "Network connection lost")
        XCTAssertFalse(pres.fillIsAnimating)
    }

    func testDoneWithoutIssueIdUsesVariantFallback() {
        let copy = IssueProgressCopy.bugDefault
        let done = IssueProgressState(progress: 1.0, phase: .done)
        XCTAssertEqual(
            ProgressPresentation.make(variant: .bug, state: done, copy: copy).badgeText,
            "BUG-—"
        )
        XCTAssertEqual(
            ProgressPresentation.make(variant: .task, state: done, copy: .taskDefault).badgeText,
            "TSK-—"
        )
        XCTAssertEqual(
            ProgressPresentation.make(variant: .story, state: done, copy: .storyDefault).badgeText,
            "STY-—"
        )
    }

    func testProgressClampsBetween0And1() {
        let copy = IssueProgressCopy.bugDefault
        let over = IssueProgressState(progress: 1.5, phase: .uploading)
        let under = IssueProgressState(progress: -0.3, phase: .uploading)
        XCTAssertEqual(ProgressPresentation.make(variant: .bug, state: over, copy: copy).fillWidthPercent, 100, accuracy: 0.001)
        XCTAssertEqual(ProgressPresentation.make(variant: .bug, state: under, copy: copy).fillWidthPercent, 0, accuracy: 0.001)
    }

    func testStageOverridesUploadingCopy() {
        let copy = IssueProgressCopy.bugDefault
        let withStage = IssueProgressState(progress: 0.3, phase: .uploading, stage: "Compressing screenshots…")
        let pres = ProgressPresentation.make(variant: .bug, state: withStage, copy: copy)
        XCTAssertEqual(pres.statusText, "Compressing screenshots…")
    }
}
