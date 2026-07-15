import XCTest
@testable import ClaudeCatCore

final class CLISupportTests: XCTestCase {
    // Fixed reference day start: 2026-07-10T05:00:00Z.
    private let dayStart = Date(timeIntervalSince1970: 1_783_659_600)

    private func makeSnapshot(
        parseErrorCount: Int = 0,
        suspiciousSkipCount: Int = 0
    ) -> DailyUsageSnapshot {
        DailyUsageSnapshot(
            dayStart: dayStart,
            counts: TokenCounts(input: 1_200, output: 300, cacheRead: 50_000, cacheCreation: 4_000),
            perModel: [
                "fable": TokenCounts(input: 1_000, output: 250, cacheRead: 40_000, cacheCreation: 3_000),
                "haiku": TokenCounts(input: 200, output: 50, cacheRead: 10_000, cacheCreation: 1_000),
            ],
            effectiveTotal: 1_834_502,
            stage: 2,
            stageCount: 6,
            tokensPerMinute: 321.5,
            isIdle: false,
            parseErrorCount: parseErrorCount,
            suspiciousSkipCount: suspiciousSkipCount,
            transcriptsFolderFound: true
        )
    }

    // MARK: - Argument parsing

    func testParseTodayWithJSONFlag() {
        XCTAssertEqual(CLISupport.parseArguments(["today", "--json"]),
                       .success(.today(json: true)))
    }

    func testParseTodayWithoutFlags() {
        XCTAssertEqual(CLISupport.parseArguments(["today"]),
                       .success(.today(json: false)))
    }

    func testParseCalibrateDefaultsToSevenDays() {
        XCTAssertEqual(CLISupport.parseArguments(["calibrate"]),
                       .success(.calibrate(days: 7)))
    }

    func testParseCalibrateWithExplicitDays() {
        XCTAssertEqual(CLISupport.parseArguments(["calibrate", "--days", "3"]),
                       .success(.calibrate(days: 3)))
    }

    func testParseWatch() {
        XCTAssertEqual(CLISupport.parseArguments(["watch"]), .success(.watch))
    }

    func testParseUnknownCommandFails() {
        XCTAssertEqual(CLISupport.parseArguments(["frobnicate"]),
                       .failure(.unknownCommand("frobnicate")))
    }

    func testParseCalibrateWithNonNumericDaysFails() {
        XCTAssertEqual(CLISupport.parseArguments(["calibrate", "--days", "x"]),
                       .failure(.invalidValue("x")))
    }

    // MARK: - JSON output

    func testSnapshotJSONDecodesBackAndContainsExpectedKeys() throws {
        let json = try CLISupport.formatSnapshotJSON(makeSnapshot())

        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let dictionary = try XCTUnwrap(object as? [String: Any])

        XCTAssertEqual(dictionary["effectiveTotal"] as? Double, 1_834_502)
        XCTAssertEqual(dictionary["stage"] as? Int, 2)
        let perModel = try XCTUnwrap(dictionary["perModel"] as? [String: Any])
        XCTAssertEqual(Set(perModel.keys), ["fable", "haiku"])
    }

    // MARK: - Human-readable snapshot

    func testHumanSnapshotContainsCoreFieldsAndOmitsCleanDiagnostics() {
        let text = CLISupport.formatSnapshot(makeSnapshot())

        XCTAssertTrue(text.contains("1.8M"), "effective total should be abbreviated")
        XCTAssertTrue(text.contains("stage"), "stage line missing")
        XCTAssertTrue(text.contains("input"), "raw breakdown missing input")
        XCTAssertTrue(text.contains("output"), "raw breakdown missing output")
        XCTAssertTrue(text.contains("cacheRead"), "raw breakdown missing cacheRead")
        XCTAssertTrue(text.contains("cacheCreation"), "raw breakdown missing cacheCreation")
        XCTAssertTrue(text.contains("fable"), "per-model line missing")
        XCTAssertTrue(text.contains("haiku"), "per-model line missing")
        XCTAssertTrue(text.contains("tokens/min"), "rate line missing")
        XCTAssertTrue(text.lowercased().contains("idle"), "idle flag missing")
        XCTAssertFalse(text.contains("parseErrors"),
                       "diagnostics must be hidden when both counters are zero")
    }

    func testHumanSnapshotShowsDiagnosticsWhenNonZero() {
        let text = CLISupport.formatSnapshot(
            makeSnapshot(parseErrorCount: 3, suspiciousSkipCount: 5)
        )

        XCTAssertTrue(text.contains("parseErrors=3"))
        XCTAssertTrue(text.contains("suspiciousSkips=5"))
    }

    // MARK: - abbreviate

    func testAbbreviateBelowThousandKeepsInteger() {
        XCTAssertEqual(CLISupport.abbreviate(950), "950")
    }

    func testAbbreviateZero() {
        XCTAssertEqual(CLISupport.abbreviate(0), "0")
    }

    func testAbbreviateMillionsWithOneDecimal() {
        XCTAssertEqual(CLISupport.abbreviate(1_834_502), "1.8M")
    }

    func testAbbreviateDropsTrailingZeroDecimal() {
        XCTAssertEqual(CLISupport.abbreviate(2_000_000), "2M")
    }

    // MARK: - Calibration table

    func testCalibrationTableRendersOneRowPerDayWithAbbreviatedEffective() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rows = [
            DailyTotal(dayStart: dayStart,
                       counts: TokenCounts(input: 1_200, output: 300,
                                           cacheRead: 50_000, cacheCreation: 4_000),
                       effective: 1_834_502),
            DailyTotal(dayStart: dayStart.addingTimeInterval(86_400),
                       counts: TokenCounts(input: 10, output: 20,
                                           cacheRead: 30, cacheCreation: 40),
                       effective: 950),
        ]

        let table = CLISupport.formatCalibrationTable(rows, calendar: calendar)
        let lines = table.split(separator: "\n").map(String.init)
        let dataLines = lines.filter { $0.contains("2026-07-") }

        XCTAssertEqual(dataLines.count, 2, "expected one row per day")
        XCTAssertTrue(dataLines[0].contains("2026-07-10"))
        XCTAssertTrue(dataLines[0].contains("1.8M"))
        XCTAssertTrue(dataLines[1].contains("2026-07-11"))
        XCTAssertTrue(dataLines[1].contains("950"))
    }
}
