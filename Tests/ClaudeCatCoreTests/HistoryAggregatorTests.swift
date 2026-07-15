import XCTest
@testable import ClaudeCatCore

final class HistoryAggregatorTests: XCTestCase {
    private var fileManager: FileManager!
    private var root: URL!
    private var dayCalculator: LogicalDayCalculator!
    private var weights: TokenWeights!
    // Fixed reference "now": 2026-07-10T12:00:00Z.
    private let now = Date(timeIntervalSince1970: 1_783_684_800)

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appendingPathComponent("HistoryAggregatorTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 7 * 3600))
        dayCalculator = LogicalDayCalculator(calendar: calendar, rolloverHour: 5)
        weights = TokenWeights()
    }

    override func tearDownWithError() throws {
        if let root, fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
        root = nil
        fileManager = nil
        dayCalculator = nil
        weights = nil
        try super.tearDownWithError()
    }

    // Builds a realistic assistant transcript line with usage, mirroring TestFixtures shape.
    private func assistantLine(
        timestamp: String, messageId: String, requestId: String,
        input: Int, output: Int, cacheRead: Int = 0, cacheCreation: Int = 0
    ) -> String {
        """
        {"parentUuid":"p-1","isSidechain":false,"userType":"external","cwd":"/Users/example/projects/demo","sessionId":"sess-1","version":"2.0.0","gitBranch":"main","type":"assistant","uuid":"u-\(messageId)","timestamp":"\(timestamp)","requestId":"\(requestId)","message":{"id":"\(messageId)","type":"message","role":"assistant","model":"claude-fable-5","content":[{"type":"text","text":"hi"}],"stop_reason":null,"usage":{"input_tokens":\(input),"cache_creation_input_tokens":\(cacheCreation),"cache_read_input_tokens":\(cacheRead),"output_tokens":\(output),"service_tier":"standard"}}}
        """
    }

    private func writeTranscript(_ relativePath: String, lines: [String],
                                 modifiedAt date: Date? = nil) throws {
        let url = root.appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        if let date {
            try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
    }

    private func isoDate(_ string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: string), "Bad fixture timestamp \(string)")
    }

    func testEventsOnTwoLogicalDaysProduceAscendingTotalsWithCorrectSums() throws {
        try writeTranscript("proj-a/session.jsonl", lines: [
            assistantLine(timestamp: "2026-07-08T10:00:00.000Z", messageId: "msg_1",
                          requestId: "req_1", input: 10, output: 20, cacheRead: 30, cacheCreation: 40),
            assistantLine(timestamp: "2026-07-08T11:00:00.000Z", messageId: "msg_2",
                          requestId: "req_2", input: 1, output: 2, cacheRead: 3, cacheCreation: 4),
            assistantLine(timestamp: "2026-07-09T10:00:00.000Z", messageId: "msg_3",
                          requestId: "req_3", input: 100, output: 200),
        ])

        let totals = HistoryAggregator.dailyTotals(
            root: root, days: 7, now: now, dayCalculator: dayCalculator,
            weights: weights, fileManager: fileManager
        )

        // Logical day 2026-07-08 (UTC+7, rollover 05:00) starts at 2026-07-07T22:00Z.
        let firstDayCounts = TokenCounts(input: 11, output: 22, cacheRead: 33, cacheCreation: 44)
        let secondDayCounts = TokenCounts(input: 100, output: 200, cacheRead: 0, cacheCreation: 0)
        XCTAssertEqual(totals, [
            DailyTotal(dayStart: try isoDate("2026-07-07T22:00:00Z"),
                       counts: firstDayCounts,
                       effective: firstDayCounts.effectiveTokens(weights: weights)),
            DailyTotal(dayStart: try isoDate("2026-07-08T22:00:00Z"),
                       counts: secondDayCounts,
                       effective: secondDayCounts.effectiveTokens(weights: weights)),
        ])
    }

    func testEventBeforeRolloverGroupsIntoPreviousLogicalDay() throws {
        // 2026-07-08T21:30Z is 04:30 local on 2026-07-09 — before the 05:00 rollover,
        // so it belongs to the logical day of 2026-07-08 (start 2026-07-07T22:00Z).
        try writeTranscript("proj-a/session.jsonl", lines: [
            assistantLine(timestamp: "2026-07-08T21:30:00.000Z", messageId: "msg_1",
                          requestId: "req_1", input: 5, output: 5),
            assistantLine(timestamp: "2026-07-08T22:30:00.000Z", messageId: "msg_2",
                          requestId: "req_2", input: 7, output: 7),
        ])

        let totals = HistoryAggregator.dailyTotals(
            root: root, days: 7, now: now, dayCalculator: dayCalculator,
            weights: weights, fileManager: fileManager
        )

        XCTAssertEqual(totals.map(\.dayStart), [
            try isoDate("2026-07-07T22:00:00Z"),
            try isoDate("2026-07-08T22:00:00Z"),
        ])
        XCTAssertEqual(totals.map(\.counts.input), [5, 7])
    }

    func testDuplicateDedupKeyAcrossTwoFilesCountedOnce() throws {
        let duplicated = assistantLine(timestamp: "2026-07-09T10:00:00.000Z", messageId: "msg_dup",
                                       requestId: "req_dup", input: 10, output: 10)
        try writeTranscript("proj-a/session.jsonl", lines: [duplicated])
        try writeTranscript("proj-b/session.jsonl", lines: [duplicated])

        let totals = HistoryAggregator.dailyTotals(
            root: root, days: 7, now: now, dayCalculator: dayCalculator,
            weights: weights, fileManager: fileManager
        )

        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals.first?.counts,
                       TokenCounts(input: 10, output: 10, cacheRead: 0, cacheCreation: 0))
    }

    func testMissingRootReturnsEmpty() {
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)

        let totals = HistoryAggregator.dailyTotals(
            root: missing, days: 7, now: now, dayCalculator: dayCalculator,
            weights: weights, fileManager: fileManager
        )

        XCTAssertEqual(totals, [])
    }

    func testEmptyRootReturnsEmpty() {
        let totals = HistoryAggregator.dailyTotals(
            root: root, days: 7, now: now, dayCalculator: dayCalculator,
            weights: weights, fileManager: fileManager
        )

        XCTAssertEqual(totals, [])
    }

    func testEventOlderThanWindowIsDroppedEvenWhenFileMtimeIsFresh() throws {
        // Event timestamp is 2 days before `now`, but the file itself was just written
        // (fresh mtime), so it passes the scanner and must be filtered per-event.
        try writeTranscript("proj-a/session.jsonl", lines: [
            assistantLine(timestamp: "2026-07-08T12:00:00.000Z", messageId: "msg_old",
                          requestId: "req_old", input: 9, output: 9),
        ], modifiedAt: now)

        let totals = HistoryAggregator.dailyTotals(
            root: root, days: 1, now: now, dayCalculator: dayCalculator,
            weights: weights, fileManager: fileManager
        )

        XCTAssertEqual(totals, [])
    }
}
