import Foundation
import XCTest
import ClaudeCatCore
import ClaudeCatPet

final class PetStateEngineTests: XCTestCase {
    private let slowestInterval: TimeInterval = 1.0
    private let fastestInterval: TimeInterval = 0.15
    private let skipThreshold = 3

    // Builds a healthy, active snapshot; individual tests override
    // only the fields relevant to the behavior under test.
    private func makeSnapshot(
        tokensPerMinute: Double = 500,
        isIdle: Bool = false,
        suspiciousSkipCount: Int = 0,
        transcriptsFolderFound: Bool = true
    ) -> DailyUsageSnapshot {
        DailyUsageSnapshot(
            dayStart: Date(timeIntervalSince1970: 0),
            counts: .zero,
            perModel: [:],
            effectiveTotal: 0,
            stage: 0,
            stageCount: 5,
            tokensPerMinute: tokensPerMinute,
            isIdle: isIdle,
            parseErrorCount: 0,
            suspiciousSkipCount: suspiciousSkipCount,
            transcriptsFolderFound: transcriptsFolderFound
        )
    }

    private func baseState(for snapshot: DailyUsageSnapshot) -> PetBehaviorState {
        PetStateEngine.baseState(snapshot: snapshot,
                                 suspiciousSkipThreshold: skipThreshold,
                                 slowestInterval: slowestInterval,
                                 fastestInterval: fastestInterval)
    }

    // MARK: - baseState precedence

    func testMissingTranscriptsFolderWinsOverIdle() {
        let snapshot = makeSnapshot(isIdle: true, transcriptsFolderFound: false)
        XCTAssertEqual(baseState(for: snapshot), .broken)
    }

    func testIdleSnapshotWithHealthyDiagnosticsSleeps() {
        let snapshot = makeSnapshot(isIdle: true)
        XCTAssertEqual(baseState(for: snapshot), .sleeping)
    }

    func testActiveSnapshotJumpsWithStageEngineInterval() {
        let rate: Double = 500
        let snapshot = makeSnapshot(tokensPerMinute: rate)
        let expected = StageEngine.frameInterval(tokensPerMinute: rate,
                                                 slowest: slowestInterval,
                                                 fastest: fastestInterval)
        XCTAssertEqual(baseState(for: snapshot), .jumping(frameInterval: expected))
    }

    func testJumpingIntervalIsClampedWithinFastestAndSlowest() {
        for rate in [0.5, 100.0, 10_000.0, 1_000_000.0] {
            guard case let .jumping(interval) = baseState(for: makeSnapshot(tokensPerMinute: rate)) else {
                XCTFail("rate \(rate) should produce .jumping")
                continue
            }
            XCTAssertGreaterThanOrEqual(interval, fastestInterval, "rate \(rate)")
            XCTAssertLessThanOrEqual(interval, slowestInterval, "rate \(rate)")
        }
    }

    // MARK: - suspicious-skip threshold boundary

    func testSkipCountExactlyAtThresholdIsNotBroken() {
        let snapshot = makeSnapshot(suspiciousSkipCount: skipThreshold)
        XCTAssertNotEqual(baseState(for: snapshot), .broken)
    }

    func testSkipCountOneAboveThresholdIsBroken() {
        let snapshot = makeSnapshot(suspiciousSkipCount: skipThreshold + 1)
        XCTAssertEqual(baseState(for: snapshot), .broken)
    }

    // MARK: - overlay precedence

    func testDraggingBeatsLiveStartle() {
        let now = Date(timeIntervalSince1970: 1_000)
        let overlay = PetStateEngine.effectiveOverlay(dragging: true,
                                                      startledUntil: now.addingTimeInterval(1),
                                                      hovering: true,
                                                      now: now)
        XCTAssertEqual(overlay, .dragging)
    }

    func testLiveStartleBeatsHovering() {
        let now = Date(timeIntervalSince1970: 1_000)
        let overlay = PetStateEngine.effectiveOverlay(dragging: false,
                                                      startledUntil: now.addingTimeInterval(1),
                                                      hovering: true,
                                                      now: now)
        XCTAssertEqual(overlay, .startled)
    }

    func testExpiredStartleFallsThroughToHovering() {
        let now = Date(timeIntervalSince1970: 1_000)
        let overlay = PetStateEngine.effectiveOverlay(dragging: false,
                                                      startledUntil: now.addingTimeInterval(-1),
                                                      hovering: true,
                                                      now: now)
        XCTAssertEqual(overlay, .hovering)
    }

    func testExpiredStartleWithoutHoveringIsNone() {
        let now = Date(timeIntervalSince1970: 1_000)
        let overlay = PetStateEngine.effectiveOverlay(dragging: false,
                                                      startledUntil: now.addingTimeInterval(-1),
                                                      hovering: false,
                                                      now: now)
        XCTAssertEqual(overlay, PetOverlay.none)
    }

    func testNoInputsYieldNoOverlay() {
        let overlay = PetStateEngine.effectiveOverlay(dragging: false,
                                                      startledUntil: nil,
                                                      hovering: false,
                                                      now: Date())
        XCTAssertEqual(overlay, PetOverlay.none)
    }

    // MARK: - clampedStage

    func testClampedStageClampsBelowZeroToZero() {
        XCTAssertEqual(PetStateEngine.clampedStage(-1, stageCount: 5), 0)
        XCTAssertEqual(PetStateEngine.clampedStage(-100, stageCount: 5), 0)
    }

    func testClampedStageClampsAtOrAboveStageCountToLastStage() {
        XCTAssertEqual(PetStateEngine.clampedStage(5, stageCount: 5), 4)
        XCTAssertEqual(PetStateEngine.clampedStage(99, stageCount: 5), 4)
    }

    func testClampedStagePassesInRangeValuesThrough() {
        for stage in 0..<5 {
            XCTAssertEqual(PetStateEngine.clampedStage(stage, stageCount: 5), stage)
        }
    }

    // MARK: - design constants

    func testSleepFrameIntervalRespectsEnergyBudget() {
        XCTAssertGreaterThanOrEqual(PetStateEngine.sleepFrameInterval, 1.0)
    }

    func testStartleDurationIsAboutTwoSeconds() {
        XCTAssertEqual(PetStateEngine.startleDuration, 2.0, accuracy: 0.5)
    }
}
