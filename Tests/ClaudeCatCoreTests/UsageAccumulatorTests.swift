import XCTest
import Foundation
@testable import ClaudeCatCore

final class UsageAccumulatorTests: XCTestCase {
    private let utcPlus7 = TimeZone(secondsFromGMT: 7 * 3600)!

    private func calendar(in zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }

    // Builds a Date from local wall-clock components in the given zone.
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0, in zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return cal.date(from: components)!
    }

    private func makeAccumulator(weights: TokenWeights = TokenWeights()) -> UsageAccumulator {
        let calculator = LogicalDayCalculator(calendar: calendar(in: utcPlus7), rolloverHour: 5)
        return UsageAccumulator(dayCalculator: calculator, weights: weights)
    }

    func testTwoDistinctEventsSumIntoTotalsAndPerModelAndEffectiveTotal() {
        var accumulator = makeAccumulator()
        let now = date(2026, 7, 10, 12, 0, in: utcPlus7)

        let opusCounts = TokenCounts(input: 100, output: 20, cacheRead: 1000, cacheCreation: 40)
        let sonnetCounts = TokenCounts(input: 30, output: 5, cacheRead: 200, cacheCreation: 10)

        let opusEvent = UsageEvent(
            timestamp: date(2026, 7, 10, 11, 0, in: utcPlus7),
            dedupKey: "msg1:req1",
            modelName: "claude-opus-4-1",
            counts: opusCounts
        )
        let sonnetEvent = UsageEvent(
            timestamp: date(2026, 7, 10, 11, 30, in: utcPlus7),
            dedupKey: "msg2:req2",
            modelName: "claude-sonnet-4-5",
            counts: sonnetCounts
        )

        XCTAssertTrue(accumulator.ingest(opusEvent, now: now))
        XCTAssertTrue(accumulator.ingest(sonnetEvent, now: now))

        XCTAssertEqual(accumulator.totals, opusCounts + sonnetCounts)
        XCTAssertEqual(accumulator.perModel[.opus], opusCounts)
        XCTAssertEqual(accumulator.perModel[.sonnet], sonnetCounts)
        XCTAssertNil(accumulator.perModel[.haiku])

        // Hand-computed with default weights (1, 5, 0.1, 1.25):
        // opus:   100*1 + 20*5 + 1000*0.1 + 40*1.25 = 100 + 100 + 100 + 50 = 350
        // sonnet: 30*1 + 5*5 + 200*0.1 + 10*1.25 = 30 + 25 + 20 + 12.5 = 87.5
        XCTAssertEqual(accumulator.effectiveTotal, 437.5, accuracy: 0.0001)
        XCTAssertEqual(accumulator.lastEventAt, sonnetEvent.timestamp)
    }

    func testDuplicateDedupKeyIsRejectedAndTotalsUnchanged() {
        var accumulator = makeAccumulator()
        let now = date(2026, 7, 10, 12, 0, in: utcPlus7)
        let counts = TokenCounts(input: 10, output: 2, cacheRead: 0, cacheCreation: 0)
        let event = UsageEvent(
            timestamp: date(2026, 7, 10, 11, 0, in: utcPlus7),
            dedupKey: "msgA:reqA",
            modelName: "claude-sonnet-4-5",
            counts: counts
        )

        XCTAssertTrue(accumulator.ingest(event, now: now))
        let totalsAfterFirst = accumulator.totals

        XCTAssertFalse(accumulator.ingest(event, now: now))
        XCTAssertEqual(accumulator.totals, totalsAfterFirst)
        XCTAssertEqual(accumulator.totals, counts)
    }

    func testNilDedupKeyEventsAreAlwaysCounted() {
        var accumulator = makeAccumulator()
        let now = date(2026, 7, 10, 12, 0, in: utcPlus7)
        let counts = TokenCounts(input: 5, output: 1, cacheRead: 0, cacheCreation: 0)
        let event = UsageEvent(
            timestamp: date(2026, 7, 10, 11, 0, in: utcPlus7),
            dedupKey: nil,
            modelName: "claude-sonnet-4-5",
            counts: counts
        )

        XCTAssertTrue(accumulator.ingest(event, now: now))
        XCTAssertTrue(accumulator.ingest(event, now: now))
        XCTAssertEqual(accumulator.totals, counts + counts)
    }

    func testEventBeforeRolloverIsIgnored() {
        var accumulator = makeAccumulator()
        // 04:30 local is before the 05:00 rollover, so it belongs to the previous logical day.
        let now = date(2026, 7, 10, 6, 0, in: utcPlus7)
        let event = UsageEvent(
            timestamp: date(2026, 7, 10, 4, 30, in: utcPlus7),
            dedupKey: "msgOld:reqOld",
            modelName: "claude-opus-4-1",
            counts: TokenCounts(input: 100, output: 100, cacheRead: 100, cacheCreation: 100)
        )

        XCTAssertFalse(accumulator.ingest(event, now: now))
        XCTAssertEqual(accumulator.totals, .zero)
        XCTAssertTrue(accumulator.perModel.isEmpty)
        XCTAssertEqual(accumulator.effectiveTotal, 0)
        XCTAssertNil(accumulator.lastEventAt)
    }

    func testResetForNewDayClearsStateAndDedupSet() {
        var accumulator = makeAccumulator()
        let now = date(2026, 7, 10, 12, 0, in: utcPlus7)
        let counts = TokenCounts(input: 10, output: 2, cacheRead: 5, cacheCreation: 1)
        let event = UsageEvent(
            timestamp: date(2026, 7, 10, 11, 0, in: utcPlus7),
            dedupKey: "msgB:reqB",
            modelName: "claude-opus-4-1",
            counts: counts
        )

        XCTAssertTrue(accumulator.ingest(event, now: now))
        accumulator.resetForNewDay()

        XCTAssertEqual(accumulator.totals, .zero)
        XCTAssertTrue(accumulator.perModel.isEmpty)
        XCTAssertEqual(accumulator.effectiveTotal, 0)
        XCTAssertNil(accumulator.lastEventAt)
        XCTAssertTrue(accumulator.recentEffective(window: 3600, now: now).isEmpty)

        // The dedup set was cleared, so the same key is accepted again.
        XCTAssertTrue(accumulator.ingest(event, now: now))
        XCTAssertEqual(accumulator.totals, counts)
    }

    func testRecentEffectiveReturnsOnlyEventsInsideWindow() {
        var accumulator = makeAccumulator()
        let now = date(2026, 7, 10, 12, 0, in: utcPlus7)
        let oldEvent = UsageEvent(
            timestamp: date(2026, 7, 10, 10, 0, in: utcPlus7),
            dedupKey: "msgOld:reqOld",
            modelName: "claude-sonnet-4-5",
            counts: TokenCounts(input: 10, output: 0, cacheRead: 0, cacheCreation: 0)
        )
        let freshEvent = UsageEvent(
            timestamp: date(2026, 7, 10, 11, 45, in: utcPlus7),
            dedupKey: "msgNew:reqNew",
            modelName: "claude-sonnet-4-5",
            counts: TokenCounts(input: 20, output: 0, cacheRead: 0, cacheCreation: 0)
        )

        XCTAssertTrue(accumulator.ingest(oldEvent, now: now))
        XCTAssertTrue(accumulator.ingest(freshEvent, now: now))

        let recent = accumulator.recentEffective(window: 30 * 60, now: now)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent[0].0, freshEvent.timestamp)
        // 20 input tokens * default weight 1.
        XCTAssertEqual(recent[0].1, 20, accuracy: 0.0001)
    }
}
