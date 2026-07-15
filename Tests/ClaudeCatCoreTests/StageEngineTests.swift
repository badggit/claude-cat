import XCTest
@testable import ClaudeCatCore

final class StageEngineTests: XCTestCase {
    // MARK: - stage(effective:thresholds:)

    func testStageBelowFirstThresholdIsZero() {
        XCTAssertEqual(StageEngine.stage(effective: 5, thresholds: [10, 20, 30, 40, 50]), 0)
    }

    func testStageBetweenThresholds() {
        XCTAssertEqual(StageEngine.stage(effective: 25, thresholds: [10, 20, 30, 40, 50]), 2)
    }

    func testStageAboveAllThresholdsIsMax() {
        XCTAssertEqual(StageEngine.stage(effective: 999, thresholds: [10, 20, 30, 40, 50]), 5)
    }

    func testStageExactlyAtThresholdBelongsToHigherStage() {
        XCTAssertEqual(StageEngine.stage(effective: 20, thresholds: [10, 20, 30, 40, 50]), 2)
    }

    func testStageWithEmptyThresholdsIsZero() {
        XCTAssertEqual(StageEngine.stage(effective: 12345, thresholds: []), 0)
    }

    // MARK: - tokensPerMinute(recent:now:window:)

    func testTokensPerMinuteEmptyRecentIsZero() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(StageEngine.tokensPerMinute(recent: [], now: now, window: 60), 0)
    }

    func testTokensPerMinuteSumsEventsInsideWindowAndNormalizes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent: [(Date, Double)] = [
            (now.addingTimeInterval(-30), 100),
            (now.addingTimeInterval(-90), 60),
            (now.addingTimeInterval(-200), 999) // outside the 120 s window, must be ignored
        ]
        // 160 tokens over a 120 s window → 80 tokens per minute
        XCTAssertEqual(StageEngine.tokensPerMinute(recent: recent, now: now, window: 120), 80, accuracy: 1e-9)
    }

    // MARK: - isIdle(lastEventAt:now:idleAfter:)

    func testIsIdleNilLastEventIsIdle() {
        XCTAssertTrue(StageEngine.isIdle(lastEventAt: nil, now: Date(), idleAfter: 300))
    }

    func testIsIdleEventOlderThanIdleAfterIsIdle() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(StageEngine.isIdle(lastEventAt: now.addingTimeInterval(-301), now: now, idleAfter: 300))
    }

    func testIsIdleRecentEventIsNotIdle() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(StageEngine.isIdle(lastEventAt: now.addingTimeInterval(-299), now: now, idleAfter: 300))
    }

    // MARK: - frameInterval(tokensPerMinute:slowest:fastest:)

    func testFrameIntervalZeroRateIsSlowest() {
        XCTAssertEqual(StageEngine.frameInterval(tokensPerMinute: 0, slowest: 1.0, fastest: 0.1), 1.0)
    }

    func testFrameIntervalAstronomicalRateClampsToFastest() {
        let interval = StageEngine.frameInterval(tokensPerMinute: 1e12, slowest: 1.0, fastest: 0.1)
        XCTAssertEqual(interval, 0.1)
        XCTAssertGreaterThanOrEqual(interval, 0.1, "interval must never drop below fastest")
    }

    func testFrameIntervalStaysWithinBoundsAndDecreasesWithRate() {
        let slow = StageEngine.frameInterval(tokensPerMinute: 100, slowest: 1.0, fastest: 0.1)
        let fast = StageEngine.frameInterval(tokensPerMinute: 10_000, slowest: 1.0, fastest: 0.1)
        XCTAssertLessThanOrEqual(slow, 1.0)
        XCTAssertGreaterThanOrEqual(slow, 0.1)
        XCTAssertLessThanOrEqual(fast, slow, "interval must be monotonically non-increasing with rate")
    }
}
