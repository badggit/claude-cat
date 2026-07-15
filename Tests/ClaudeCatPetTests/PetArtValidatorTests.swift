import XCTest
import ClaudeCatPet

final class PetArtValidatorTests: XCTestCase {
    // Small local palette; the real one arrives with the generated art data.
    private let palette = PetPalette(colors: [
        "#": PetColor(r: 10, g: 20, b: 30, a: 255),
        "o": PetColor(r: 200, g: 200, b: 200, a: 255)
    ])

    // MARK: - Fixture builders

    private func transparentRows() -> [String] {
        Array(repeating: String(repeating: ".", count: petGrid), count: petGrid)
    }

    // A 64x64 frame with a small opaque body and (optionally) one accent pixel.
    private func validFrame(accent: Bool = true) -> PetFrame {
        var rows = transparentRows()
        rows[10] = "###" + String(repeating: ".", count: petGrid - 3)
        if accent {
            rows[11] = "@" + String(repeating: ".", count: petGrid - 1)
        }
        return PetFrame(rows: rows)
    }

    private func validStage(jumpFrames: Int = 2) -> PetStageSprites {
        PetStageSprites(jump: (0..<jumpFrames).map { _ in validFrame() },
                        sleep: [validFrame(), validFrame()],
                        drag: validFrame(),
                        hover: validFrame())
    }

    private func validCreature(stages: [PetStageSprites]? = nil,
                               broken: [PetFrame]? = nil) -> PetCreatureArt {
        PetCreatureArt(id: "synthetic",
                       displayName: "Synthetic",
                       stages: stages ?? (0..<6).map { _ in validStage() },
                       broken: broken ?? [validFrame()])
    }

    // MARK: - Happy path

    func testSyntheticValidCreatureProducesZeroIssues() {
        let issues = PetArtValidator.issues(in: validCreature(), palette: palette)
        XCTAssertEqual(issues, [])
    }

    // MARK: - Geometry

    func testShortRowProducesIssueContainingRowIndex() {
        var rows = validFrame().rows
        rows[20] = String(rows[20].dropLast())
        var stages = (0..<6).map { _ in validStage() }
        stages[0] = PetStageSprites(jump: [PetFrame(rows: rows), validFrame()],
                                    sleep: [validFrame(), validFrame()],
                                    drag: validFrame(),
                                    hover: validFrame())
        let issues = PetArtValidator.issues(in: validCreature(stages: stages), palette: palette)
        XCTAssertTrue(issues.contains { $0.contains("row 20") },
                      "expected an issue naming row 20, got \(issues)")
    }

    func testWrongRowCountProducesIssue() {
        let truncated = PetFrame(rows: Array(validFrame().rows.dropLast()))
        let issues = PetArtValidator.issues(in: validCreature(broken: [truncated]),
                                            palette: palette)
        XCTAssertTrue(issues.contains { $0.contains("63") && $0.contains("rows") },
                      "expected a row-count issue, got \(issues)")
    }

    // MARK: - Characters and palette

    func testCharacterAbsentFromPaletteProducesIssueNamingIt() {
        var rows = validFrame().rows
        rows[30] = "Z" + String(repeating: ".", count: petGrid - 1)
        let issues = PetArtValidator.issues(in: validCreature(broken: [PetFrame(rows: rows)]),
                                            palette: palette)
        XCTAssertTrue(issues.contains { $0.contains("'Z'") },
                      "expected an issue naming character 'Z', got \(issues)")
    }

    func testFullyTransparentFrameProducesEmptyFrameIssue() {
        let empty = PetFrame(rows: transparentRows())
        let issues = PetArtValidator.issues(in: validCreature(broken: [empty]),
                                            palette: palette)
        XCTAssertTrue(issues.contains { $0.contains("empty frame") },
                      "expected an empty-frame issue, got \(issues)")
    }

    // MARK: - Structure counts

    func testFiveStagesProducesStageCountIssue() {
        let creature = validCreature(stages: (0..<5).map { _ in validStage() })
        let issues = PetArtValidator.issues(in: creature, palette: palette)
        XCTAssertTrue(issues.contains { $0.contains("stages") && $0.contains("5") },
                      "expected a stage-count issue, got \(issues)")
    }

    func testSingleJumpFrameProducesIssue() {
        var stages = (0..<6).map { _ in validStage() }
        stages[2] = PetStageSprites(jump: [validFrame()],
                                    sleep: [validFrame(), validFrame()],
                                    drag: validFrame(),
                                    hover: validFrame())
        let issues = PetArtValidator.issues(in: validCreature(stages: stages), palette: palette)
        XCTAssertTrue(issues.contains { $0.contains("jump") && $0.contains("stage 2") },
                      "expected a jump frame-count issue for stage 2, got \(issues)")
    }

    func testSingleSleepFrameProducesIssue() {
        var stages = (0..<6).map { _ in validStage() }
        stages[4] = PetStageSprites(jump: [validFrame(), validFrame()],
                                    sleep: [validFrame()],
                                    drag: validFrame(),
                                    hover: validFrame())
        let issues = PetArtValidator.issues(in: validCreature(stages: stages), palette: palette)
        XCTAssertTrue(issues.contains { $0.contains("sleep") && $0.contains("stage 4") },
                      "expected a sleep frame-count issue for stage 4, got \(issues)")
    }

    func testNoBrokenFramesProducesIssue() {
        let issues = PetArtValidator.issues(in: validCreature(broken: []), palette: palette)
        XCTAssertTrue(issues.contains { $0.contains("broken") },
                      "expected a broken frame-count issue, got \(issues)")
    }

    // MARK: - Global accent rule

    func testNonBrokenFrameWithoutAccentProducesIssueNamingFrame() {
        var stages = (0..<6).map { _ in validStage() }
        stages[3] = PetStageSprites(jump: [validFrame(), validFrame()],
                                    sleep: [validFrame(), validFrame()],
                                    drag: validFrame(),
                                    hover: validFrame(accent: false))
        let issues = PetArtValidator.issues(in: validCreature(stages: stages), palette: palette)
        XCTAssertTrue(issues.contains { $0.contains("@") && $0.contains("stage 3") && $0.contains("hover") },
                      "expected an accent issue naming stage 3 hover, got \(issues)")
    }

    func testBrokenFrameWithoutAccentProducesNoIssues() {
        let issues = PetArtValidator.issues(in: validCreature(broken: [validFrame(accent: false)]),
                                            palette: palette)
        XCTAssertEqual(issues, [])
    }

    // MARK: - Stage clamping

    func testStageSpritesClampsOutOfRangeToFirstAndLastStage() {
        // Jump frame counts 2...7 make each stage distinguishable.
        let creature = validCreature(stages: (0..<6).map { validStage(jumpFrames: $0 + 2) })
        XCTAssertEqual(creature.stageSprites(stage: -1).jump.count, 2)
        XCTAssertEqual(creature.stageSprites(stage: 99).jump.count, 7)
        XCTAssertEqual(creature.stageSprites(stage: 3).jump.count, 5)
    }

    // MARK: - Accent color mapping

    func testAccentColorPinsFamilyColors() {
        XCTAssertEqual(PetPalette.accentColor(for: .opus), PetColor(r: 230, g: 126, b: 34, a: 255))
        XCTAssertEqual(PetPalette.accentColor(for: .sonnet), PetColor(r: 52, g: 120, b: 246, a: 255))
        XCTAssertEqual(PetPalette.accentColor(for: .haiku), PetColor(r: 46, g: 174, b: 82, a: 255))
        XCTAssertEqual(PetPalette.accentColor(for: .fable), PetColor(r: 155, g: 89, b: 182, a: 255))
    }

    func testAccentColorFallsBackToNeutralGray() {
        let gray = PetColor(r: 142, g: 142, b: 147, a: 255)
        XCTAssertEqual(PetPalette.accentColor(for: .other), gray)
        XCTAssertEqual(PetPalette.accentColor(for: nil), gray)
    }
}
