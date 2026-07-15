import XCTest
@testable import ClaudeCatCore

final class TranscriptLineParserTests: XCTestCase {
    // Unwraps the .event case or fails the test with a readable message.
    private func expectEvent(
        _ line: String,
        file: StaticString = #filePath,
        line lineNumber: UInt = #line
    ) throws -> UsageEvent {
        let outcome = TranscriptLineParser.parse(line: line)
        guard case .event(let event) = outcome else {
            XCTFail("Expected .event, got \(outcome)", file: file, line: lineNumber)
            throw XCTSkip("No event to inspect")
        }
        return event
    }

    func testFullAssistantLineProducesEvent() throws {
        let event = try expectEvent(TestFixtures.assistantFullUsage)
        XCTAssertEqual(
            event.counts,
            TokenCounts(input: 12, output: 42, cacheRead: 6789, cacheCreation: 345)
        )
        XCTAssertEqual(event.modelName, "claude-fable-5")
        XCTAssertEqual(event.dedupKey, "msg_1:req_1")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(event.timestamp, formatter.date(from: "2026-07-10T19:16:50.064Z"))
    }

    func testNonFractionalTimestampParses() throws {
        let event = try expectEvent(TestFixtures.assistantNonFractionalTimestamp)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        XCTAssertEqual(event.timestamp, formatter.date(from: "2026-07-10T19:31:00Z"))
    }

    func testUserMessageIsSkippedIrrelevant() {
        XCTAssertEqual(TranscriptLineParser.parse(line: TestFixtures.userMessage), .skippedIrrelevant)
    }

    func testToolResultLineIsSkippedIrrelevant() {
        XCTAssertEqual(TranscriptLineParser.parse(line: TestFixtures.toolResult), .skippedIrrelevant)
    }

    func testAssistantWithoutUsageIsFlagged() {
        XCTAssertEqual(
            TranscriptLineParser.parse(line: TestFixtures.assistantWithoutUsage),
            .assistantWithoutUsage
        )
    }

    func testMissingRequestIdFallsBackToMessageId() throws {
        let event = try expectEvent(TestFixtures.assistantMissingRequestId)
        XCTAssertEqual(event.dedupKey, "msg_6")
    }

    func testMissingBothIdsYieldsNilDedupKey() throws {
        let event = try expectEvent(TestFixtures.assistantMissingBothIds)
        XCTAssertNil(event.dedupKey)
    }

    func testAbsentCacheReadDefaultsToZero() throws {
        let event = try expectEvent(TestFixtures.assistantMissingCacheRead)
        XCTAssertEqual(
            event.counts,
            TokenCounts(input: 10, output: 30, cacheRead: 0, cacheCreation: 20)
        )
    }

    func testBrokenJsonPassingPrefilterIsMalformed() {
        XCTAssertEqual(TranscriptLineParser.parse(line: TestFixtures.brokenJson), .malformed)
    }

    func testUnparseableTimestampIsMalformed() {
        XCTAssertEqual(
            TranscriptLineParser.parse(line: TestFixtures.assistantBadTimestamp),
            .malformed
        )
    }
}
