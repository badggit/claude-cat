import Foundation

// Computes logical day boundaries where a "day" starts at rolloverHour:00
// local time (per the injected calendar's time zone) instead of midnight.
// Pure date math: never touches TimeZone.current — the calendar carries the zone.
public struct LogicalDayCalculator {
    private let calendar: Calendar
    private let rolloverHour: Int

    public init(calendar: Calendar, rolloverHour: Int) {
        self.calendar = calendar
        self.rolloverHour = rolloverHour
    }

    // Most recent rolloverHour:00 at or before the given date.
    public func dayStart(containing date: Date) -> Date {
        let midnight = calendar.startOfDay(for: date)
        guard let rolloverToday = calendar.date(byAdding: .hour, value: rolloverHour, to: midnight) else {
            return midnight
        }
        if rolloverToday <= date {
            return rolloverToday
        }
        // Before today's rollover: the logical day started at rolloverHour of the previous calendar date.
        return calendar.date(byAdding: .day, value: -1, to: rolloverToday) ?? rolloverToday
    }

    public func isInCurrentDay(_ timestamp: Date, now: Date) -> Bool {
        timestamp >= dayStart(containing: now) && timestamp <= now
    }
}
