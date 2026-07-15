import XCTest
import Foundation
@testable import ClaudeCatCore

final class LogicalDayCalculatorTests: XCTestCase {
    // UTC+7 zone deliberately differs from UTC to expose implicit-timezone bugs,
    // since transcript timestamps are UTC.
    private let utcPlus7 = TimeZone(secondsFromGMT: 7 * 3600)!
    private let utc = TimeZone(secondsFromGMT: 0)!

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

    func testDayStartAfterRolloverIsSameCalendarDate() {
        let cal = calendar(in: utcPlus7)
        let calculator = LogicalDayCalculator(calendar: cal, rolloverHour: 5)
        let now = date(2026, 7, 10, 6, 0, in: utcPlus7)
        let expected = date(2026, 7, 10, 5, 0, in: utcPlus7)
        XCTAssertEqual(calculator.dayStart(containing: now), expected)
    }

    func testDayStartBeforeRolloverIsPreviousCalendarDate() {
        let cal = calendar(in: utcPlus7)
        let calculator = LogicalDayCalculator(calendar: cal, rolloverHour: 5)
        let now = date(2026, 7, 10, 4, 59, in: utcPlus7)
        let expected = date(2026, 7, 9, 5, 0, in: utcPlus7)
        XCTAssertEqual(calculator.dayStart(containing: now), expected)
    }

    func testDayStartExactlyAtRolloverIsThatSameInstant() {
        let cal = calendar(in: utcPlus7)
        let calculator = LogicalDayCalculator(calendar: cal, rolloverHour: 5)
        let now = date(2026, 7, 10, 5, 0, 0, in: utcPlus7)
        XCTAssertEqual(calculator.dayStart(containing: now), now)
    }

    func testEventBeforeRolloverIsNotInCurrentDay() {
        let cal = calendar(in: utcPlus7)
        let calculator = LogicalDayCalculator(calendar: cal, rolloverHour: 5)
        let event = date(2026, 7, 10, 4, 30, in: utcPlus7)
        let now = date(2026, 7, 10, 6, 0, in: utcPlus7)
        XCTAssertFalse(calculator.isInCurrentDay(event, now: now))
    }

    func testEventAfterRolloverIsInCurrentDay() {
        let cal = calendar(in: utcPlus7)
        let calculator = LogicalDayCalculator(calendar: cal, rolloverHour: 5)
        let event = date(2026, 7, 10, 5, 10, in: utcPlus7)
        let now = date(2026, 7, 10, 6, 0, in: utcPlus7)
        XCTAssertTrue(calculator.isInCurrentDay(event, now: now))
    }

    // Guards against implicit-timezone regressions: the same absolute instants
    // must be classified differently by a UTC calendar vs a UTC+7 calendar.
    func testSameInstantsClassifiedDifferentlyInUTCVersusUTCPlus7() {
        // Event at 2026-07-10 04:30 local UTC+7 == 2026-07-09 21:30 UTC.
        // Now at 2026-07-10 06:00 local UTC+7 == 2026-07-09 23:00 UTC.
        let event = date(2026, 7, 10, 4, 30, in: utcPlus7)
        let now = date(2026, 7, 10, 6, 0, in: utcPlus7)

        let localCalculator = LogicalDayCalculator(calendar: calendar(in: utcPlus7), rolloverHour: 5)
        let utcCalculator = LogicalDayCalculator(calendar: calendar(in: utc), rolloverHour: 5)

        let localResult = localCalculator.isInCurrentDay(event, now: now)
        let utcResult = utcCalculator.isInCurrentDay(event, now: now)

        // In UTC+7 the event falls before the 05:00 rollover (previous logical day),
        // while in UTC both instants are between 05:00 and next 05:00 of 2026-07-09.
        XCTAssertFalse(localResult)
        XCTAssertTrue(utcResult)
        XCTAssertNotEqual(localResult, utcResult)
    }
}
