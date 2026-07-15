import Foundation
import XCTest
@testable import ClaudeCatCore

final class LaunchAgentPlistTests: XCTestCase {
    // Parses generated XML back into a dictionary; fails the test on malformed output.
    private func parse(_ xml: String, file: StaticString = #filePath,
                       line: UInt = #line) throws -> [String: Any] {
        let data = try XCTUnwrap(xml.data(using: .utf8), file: file, line: line)
        let object = try PropertyListSerialization.propertyList(from: data,
                                                                options: [],
                                                                format: nil)
        return try XCTUnwrap(object as? [String: Any], file: file, line: line)
    }

    func testXMLContainsLabelAndPathAndCoreKeys() throws {
        let path = "/Users/tester/bin/claude-cat-app"
        let xml = LaunchAgentPlist.xml(executablePath: path, environment: [:])

        XCTAssertTrue(xml.contains(LaunchAgentPlist.label))
        XCTAssertTrue(xml.contains(path))

        let dict = try parse(xml)
        XCTAssertEqual(dict["Label"] as? String, "com.claudecat.app")
        XCTAssertEqual(dict["ProgramArguments"] as? [String], [path])
        XCTAssertEqual(dict["RunAtLoad"] as? Bool, true)
        // KeepAlive MUST be false: true would make launchd resurrect the app after Quit.
        XCTAssertEqual(dict["KeepAlive"] as? Bool, false)
    }

    func testEnvironmentVariablesEmbeddedWhenProvided() throws {
        let xml = LaunchAgentPlist.xml(executablePath: "/usr/local/bin/claude-cat-app",
                                       environment: ["CLAUDE_CAT_PROJECTS_DIR": "/tmp/x"])
        let dict = try parse(xml)
        let env = try XCTUnwrap(dict["EnvironmentVariables"] as? [String: String])
        XCTAssertEqual(env, ["CLAUDE_CAT_PROJECTS_DIR": "/tmp/x"])
    }

    func testEmptyEnvironmentOmitsEnvironmentVariablesKey() throws {
        let xml = LaunchAgentPlist.xml(executablePath: "/usr/local/bin/claude-cat-app",
                                       environment: [:])
        let dict = try parse(xml)
        XCTAssertNil(dict["EnvironmentVariables"])
    }

    func testPathWithSpacesSurvivesRoundTrip() throws {
        let path = "/Users/tester/My Apps/claude cat/claude-cat-app"
        let xml = LaunchAgentPlist.xml(executablePath: path, environment: [:])
        let dict = try parse(xml)
        XCTAssertEqual(dict["ProgramArguments"] as? [String], [path])
    }

    func testOutputDeclaresPlistVersionAndParses() throws {
        let xml = LaunchAgentPlist.xml(executablePath: "/usr/local/bin/claude-cat-app",
                                       environment: [:])
        XCTAssertTrue(xml.contains("plist version=\"1.0\""))
        XCTAssertNoThrow(try parse(xml))
    }
}
