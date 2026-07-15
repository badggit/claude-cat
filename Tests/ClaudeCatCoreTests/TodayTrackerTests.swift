import XCTest
@testable import ClaudeCatCore

final class TodayTrackerTests: XCTestCase {
    private var fileManager: FileManager!
    private var root: URL!
    // UTC+7 calendar: with rolloverHour 5 the logical day starts at 22:00 UTC of the previous UTC day.
    private var calendar: Calendar!

    // Fixed instants (UTC). Logical day 1 spans [2026-07-09T22:00Z, 2026-07-10T22:00Z).
    private let day1Start = TodayTrackerTests.isoDate("2026-07-09T22:00:00Z")
    private let day2Start = TodayTrackerTests.isoDate("2026-07-10T22:00:00Z")
    private let now1 = TodayTrackerTests.isoDate("2026-07-10T20:00:00Z")
    private let now2 = TodayTrackerTests.isoDate("2026-07-10T20:01:00Z")
    private let nowAfterRollover = TodayTrackerTests.isoDate("2026-07-10T23:00:00Z")
    private let nowAfterRolloverLater = TodayTrackerTests.isoDate("2026-07-10T23:05:00Z")

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appendingPathComponent("TodayTrackerTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
    }

    override func tearDownWithError() throws {
        if let root, fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
        root = nil
        fileManager = nil
        calendar = nil
        try super.tearDownWithError()
    }

    private static func isoDate(_ raw: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: raw) else {
            fatalError("Bad fixture date: \(raw)")
        }
        return date
    }

    // Unit weights so effectiveTotal equals the plain token sum; thresholds
    // small enough for fixture-sized counts to exercise non-zero stages.
    private func makeConfig(projectsRoot: URL) -> ClaudeCatConfig {
        ClaudeCatConfig(
            rolloverHour: 5,
            pollIntervalSeconds: 15,
            rateWindowSeconds: 300,
            idleAfterSeconds: 300,
            weights: TokenWeights(input: 1, output: 1, cacheRead: 1, cacheCreation: 1),
            stageThresholds: [30, 100],
            suspiciousSkipThreshold: 10,
            projectsRoot: projectsRoot
        )
    }

    private func makeTracker(projectsRoot: URL? = nil) -> TodayTracker {
        TodayTracker(config: makeConfig(projectsRoot: projectsRoot ?? root),
                     calendar: calendar,
                     fileManager: fileManager)
    }

    // Realistic assistant jsonl line mirroring TestFixtures; nil ids produce
    // a record with no dedup key at all.
    private func assistantLine(messageId: String?, requestId: String?, timestamp: String,
                               input: Int, output: Int,
                               model: String = "claude-fable-5") -> String {
        var messageFields = ""
        if let messageId {
            messageFields += "\"id\":\"\(messageId)\","
        }
        let requestField = requestId.map { "\"requestId\":\"\($0)\"," } ?? ""
        return "{\"parentUuid\":\"p-1\",\"isSidechain\":false,\"userType\":\"external\"," +
            "\"cwd\":\"/Users/example/projects/demo\",\"sessionId\":\"sess-1\"," +
            "\"type\":\"assistant\",\"uuid\":\"u-\(UUID().uuidString)\"," +
            "\"timestamp\":\"\(timestamp)\",\(requestField)" +
            "\"message\":{\(messageFields)\"type\":\"message\",\"role\":\"assistant\"," +
            "\"model\":\"\(model)\",\"content\":[{\"type\":\"text\",\"text\":\"Hi\"}]," +
            "\"usage\":{\"input_tokens\":\(input),\"cache_creation_input_tokens\":0," +
            "\"cache_read_input_tokens\":0,\"output_tokens\":\(output),\"service_tier\":\"standard\"}}}"
    }

    // Assistant record whose message has no usage object; contains the word
    // "usage" in its text so the parser prefilter still decodes it.
    private func assistantLineWithoutUsage(timestamp: String) -> String {
        "{\"type\":\"assistant\",\"uuid\":\"u-\(UUID().uuidString)\",\"timestamp\":\"\(timestamp)\"," +
            "\"requestId\":\"req-\(UUID().uuidString)\"," +
            "\"message\":{\"id\":\"msg-\(UUID().uuidString)\",\"type\":\"message\",\"role\":\"assistant\"," +
            "\"model\":\"claude-fable-5\",\"content\":[{\"type\":\"text\",\"text\":\"token usage report\"}]}}"
    }

    // Writes (or appends) newline-terminated lines and pins the file mtime so
    // candidate filtering (mtime >= dayStart) is deterministic in tests.
    private func write(lines: [String], to relativePath: String,
                       mtime: Date, append: Bool = false) throws {
        let url = root.appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        let payload = Data((lines.joined(separator: "\n") + "\n").utf8)
        if append, fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } else {
            try payload.write(to: url)
        }
        try fileManager.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
    }

    // MARK: - Happy path

    func testFirstRefreshAccumulatesAndSecondRefreshIsIncremental() throws {
        // Both lines lack message.id and requestId (dedupKey == nil), so a
        // full recount instead of an incremental read would double the totals.
        try write(lines: [
            assistantLine(messageId: nil, requestId: nil,
                          timestamp: "2026-07-10T19:16:50.064Z", input: 10, output: 5),
            assistantLine(messageId: nil, requestId: nil,
                          timestamp: "2026-07-10T19:31:00Z", input: 20, output: 5)
        ], to: "proj/session.jsonl", mtime: now1)

        let tracker = makeTracker()
        let first = tracker.refresh(now: now1)

        XCTAssertEqual(first.dayStart, day1Start)
        XCTAssertEqual(first.counts, TokenCounts(input: 30, output: 10, cacheRead: 0, cacheCreation: 0))
        XCTAssertEqual(first.effectiveTotal, 40, accuracy: 0.0001)
        XCTAssertEqual(first.stage, 1)
        XCTAssertEqual(first.stageCount, 3)
        XCTAssertEqual(first.perModel,
                       ["fable": TokenCounts(input: 30, output: 10, cacheRead: 0, cacheCreation: 0)])
        // Fixture lines use "claude-fable-5", so the last ingested family is fable.
        XCTAssertEqual(first.lastModelFamily, .fable)
        // Last event was 29 minutes before now1 — outside the 300 s rate window.
        XCTAssertEqual(first.tokensPerMinute, 0, accuracy: 0.0001)
        XCTAssertTrue(first.isIdle)
        XCTAssertEqual(first.parseErrorCount, 0)
        XCTAssertEqual(first.suspiciousSkipCount, 0)
        XCTAssertTrue(first.transcriptsFolderFound)

        try write(lines: [
            assistantLine(messageId: nil, requestId: nil,
                          timestamp: "2026-07-10T20:00:30Z", input: 6, output: 4)
        ], to: "proj/session.jsonl", mtime: now2, append: true)

        let second = tracker.refresh(now: now2)

        XCTAssertEqual(second.counts, TokenCounts(input: 36, output: 14, cacheRead: 0, cacheCreation: 0))
        XCTAssertEqual(second.effectiveTotal, 50, accuracy: 0.0001)
        // Only the freshly appended 10 effective tokens fall inside the window.
        XCTAssertEqual(second.tokensPerMinute, 10 * 60 / 300, accuracy: 0.0001)
        XCTAssertFalse(second.isIdle)
    }

    // MARK: - Mid-day file reset

    func testTruncateAndRewriteWithKeylessEventsDoesNotDoubleCount() throws {
        // All events lack dedup keys, so only a full-day rebuild (not dedup)
        // can protect against re-counting after the file is replaced.
        let originalLines = [
            assistantLine(messageId: nil, requestId: nil,
                          timestamp: "2026-07-10T19:16:50.064Z", input: 10, output: 5),
            assistantLine(messageId: nil, requestId: nil,
                          timestamp: "2026-07-10T19:31:00Z", input: 20, output: 5)
        ]
        try write(lines: originalLines, to: "proj/session.jsonl", mtime: now1)

        let tracker = makeTracker()
        let first = tracker.refresh(now: now1)
        XCTAssertEqual(first.counts, TokenCounts(input: 30, output: 10, cacheRead: 0, cacheCreation: 0))
        XCTAssertEqual(first.effectiveTotal, 40, accuracy: 0.0001)

        // Atomically replace the file with the SAME keyless content plus one
        // new event, mimicking a mid-day truncate-and-rewrite. The replacement
        // is larger than the consumed offset, so only the identity (inode)
        // check can reveal the reset.
        let newLine = assistantLine(messageId: nil, requestId: nil,
                                    timestamp: "2026-07-10T20:00:30Z", input: 6, output: 4)
        let url = root.appendingPathComponent("proj/session.jsonl")
        let replacement = root.appendingPathComponent("proj/replacement.tmp")
        let payload = Data(((originalLines + [newLine]).joined(separator: "\n") + "\n").utf8)
        try payload.write(to: replacement)
        try fileManager.removeItem(at: url)
        try fileManager.moveItem(at: replacement, to: url)
        try fileManager.setAttributes([.modificationDate: now2], ofItemAtPath: url.path)

        // The rebuild must count the original content exactly ONCE plus the
        // new event — never 40 + 50 = 90.
        let second = tracker.refresh(now: now2)
        XCTAssertEqual(second.counts, TokenCounts(input: 36, output: 14, cacheRead: 0, cacheCreation: 0))
        XCTAssertEqual(second.effectiveTotal, 50, accuracy: 0.0001)
        XCTAssertEqual(second.parseErrorCount, 0)
        XCTAssertEqual(second.suspiciousSkipCount, 0)
    }

    // MARK: - Day rollover

    func testRolloverResetsTotalsAndCountsNewDayEvents() throws {
        try write(lines: [
            assistantLine(messageId: "msg_1", requestId: "req_1",
                          timestamp: "2026-07-10T19:16:50.064Z", input: 10, output: 5)
        ], to: "proj/session.jsonl", mtime: now1)

        let tracker = makeTracker()
        let beforeRollover = tracker.refresh(now: now1)
        XCTAssertEqual(beforeRollover.dayStart, day1Start)
        XCTAssertEqual(beforeRollover.effectiveTotal, 15, accuracy: 0.0001)

        // Keep the file inside the new day's mtime cutoff without new content.
        try fileManager.setAttributes([.modificationDate: nowAfterRollover],
                                      ofItemAtPath: root.appendingPathComponent("proj/session.jsonl").path)
        let afterRollover = tracker.refresh(now: nowAfterRollover)

        XCTAssertEqual(afterRollover.dayStart, day2Start)
        XCTAssertEqual(afterRollover.counts, .zero)
        XCTAssertEqual(afterRollover.effectiveTotal, 0, accuracy: 0.0001)
        XCTAssertEqual(afterRollover.stage, 0)
        XCTAssertTrue(afterRollover.isIdle)

        try write(lines: [
            assistantLine(messageId: "msg_2", requestId: "req_2",
                          timestamp: "2026-07-10T22:30:00Z", input: 7, output: 3)
        ], to: "proj/session.jsonl", mtime: nowAfterRolloverLater, append: true)

        let newDay = tracker.refresh(now: nowAfterRolloverLater)
        XCTAssertEqual(newDay.dayStart, day2Start)
        XCTAssertEqual(newDay.counts, TokenCounts(input: 7, output: 3, cacheRead: 0, cacheCreation: 0))
        XCTAssertEqual(newDay.effectiveTotal, 10, accuracy: 0.0001)
    }

    // MARK: - Missing root

    func testMissingRootDirectoryYieldsEmptySnapshotWithoutCrashing() {
        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)
        let tracker = makeTracker(projectsRoot: missing)

        let snapshot = tracker.refresh(now: now1)

        XCTAssertFalse(snapshot.transcriptsFolderFound)
        XCTAssertEqual(snapshot.counts, .zero)
        XCTAssertEqual(snapshot.effectiveTotal, 0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.stage, 0)
        XCTAssertTrue(snapshot.isIdle)
    }

    // MARK: - Malformed lines and duplicates

    func testMalformedLinesCountedAndDuplicateLineIgnored() throws {
        let validLine = assistantLine(messageId: "msg_1", requestId: "req_1",
                                      timestamp: "2026-07-10T19:16:50.064Z", input: 10, output: 5)
        // Broken JSON that still passes the "assistant"/"usage" prefilter.
        let broken = "{ not json \"assistant\" \"usage\""
        try write(lines: [validLine, broken, broken],
                  to: "proj/session.jsonl", mtime: now1)

        let tracker = makeTracker()
        let first = tracker.refresh(now: now1)

        XCTAssertEqual(first.counts, TokenCounts(input: 10, output: 5, cacheRead: 0, cacheCreation: 0))
        XCTAssertEqual(first.parseErrorCount, 2)

        // Re-appending the same line must be deduplicated by messageId:requestId.
        try write(lines: [validLine], to: "proj/session.jsonl", mtime: now2, append: true)
        let second = tracker.refresh(now: now2)

        XCTAssertEqual(second.counts, TokenCounts(input: 10, output: 5, cacheRead: 0, cacheCreation: 0))
        XCTAssertEqual(second.effectiveTotal, 15, accuracy: 0.0001)
        XCTAssertEqual(second.parseErrorCount, 2)
    }

    // MARK: - Assistant records without usage

    func testAssistantRecordsWithoutUsageAreCountedAsSuspicious() throws {
        try write(lines: [
            assistantLineWithoutUsage(timestamp: "2026-07-10T19:16:50.064Z"),
            assistantLineWithoutUsage(timestamp: "2026-07-10T19:17:00.000Z")
        ], to: "proj/session.jsonl", mtime: now1)

        let tracker = makeTracker()
        let snapshot = tracker.refresh(now: now1)

        XCTAssertEqual(snapshot.counts, .zero)
        XCTAssertEqual(snapshot.effectiveTotal, 0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.suspiciousSkipCount, 2)
        XCTAssertEqual(snapshot.parseErrorCount, 0)
    }
}
