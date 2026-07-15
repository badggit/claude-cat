import XCTest
@testable import ClaudeCatCore

final class UsageModelsTests: XCTestCase {
    func testEffectiveTokensWithDefaultWeights() {
        let counts = TokenCounts(input: 100, output: 10, cacheRead: 1000, cacheCreation: 40)
        let effective = counts.effectiveTokens(weights: TokenWeights())
        // 100*1 + 10*5 + 1000*0.1 + 40*1.25 = 100 + 50 + 100 + 50 = 300
        XCTAssertEqual(effective, 300.0, accuracy: 0.0001)
    }

    func testZeroCountsHaveZeroEffectiveTokens() {
        XCTAssertEqual(TokenCounts.zero.effectiveTokens(weights: TokenWeights()), 0.0, accuracy: 0.0001)
    }

    func testModelFamilyMatchesKnownFamilies() {
        XCTAssertEqual(ModelFamily(modelName: "claude-opus-4-8"), .opus)
        XCTAssertEqual(ModelFamily(modelName: "claude-sonnet-5"), .sonnet)
    }

    func testModelFamilyNilFallsBackToOther() {
        XCTAssertEqual(ModelFamily(modelName: nil), .other)
    }

    func testModelFamilyUnknownNameFallsBackToOther() {
        XCTAssertEqual(ModelFamily(modelName: "gpt-9000"), .other)
    }

    func testConfigProjectsRootEnvironmentOverride() {
        let config = ClaudeCatConfig.standard(environment: ["CLAUDE_CAT_PROJECTS_DIR": "/tmp/x"])
        XCTAssertEqual(config.projectsRoot.path, "/tmp/x")
    }

    func testConfigProjectsRootDefaultsToClaudeProjects() {
        let config = ClaudeCatConfig.standard(environment: [:])
        XCTAssertTrue(config.projectsRoot.path.hasSuffix(".claude/projects"))
    }
}
