import XCTest
import ClaudeCatPet

final class PetArtCatalogTests: XCTestCase {
    private static let menuBarCreatureIDs = ["cat", "bunny", "bird", "flower", "pig"]
    private static let pixelArtCreatureIDs = ["bunny", "bird", "flower", "pig"]

    func testVisualCatalogMatchesMenuBarCreatureIdsInOrder() {
        XCTAssertEqual(PetVisualCatalog.all.map { $0.id }, Self.menuBarCreatureIDs)
    }

    func testCatVisualUsesIllustrationWithSixStages() throws {
        let cat = try XCTUnwrap(PetVisualCatalog.visual(id: "cat"))

        XCTAssertEqual(cat.displayName, "Cat")
        XCTAssertEqual(cat.stageCount, 6)
        XCTAssertEqual(cat.kind, .illustratedCat)
        XCTAssertEqual(PetVisualCatalog.stageCount(for: "cat"), 6)
    }

    func testNonCatVisualsUsePixelArtWithSixStages() throws {
        for id in Self.pixelArtCreatureIDs {
            let visual = try XCTUnwrap(PetVisualCatalog.visual(id: id), "missing visual '\(id)'")

            XCTAssertEqual(visual.stageCount, 6, "visual '\(id)' stage count")
            XCTAssertEqual(visual.kind, .pixelArt, "visual '\(id)' kind")
            XCTAssertEqual(PetVisualCatalog.stageCount(for: id), 6)
        }
    }

    func testUnknownVisualLookupFailsSafely() {
        XCTAssertNil(PetVisualCatalog.visual(id: "no-such-creature"))
        XCTAssertNil(PetVisualCatalog.stageCount(for: "no-such-creature"))
    }

    func testPixelArtCatalogContainsOnlyNonCatCreaturesInOrder() {
        XCTAssertEqual(PetArtCatalog.all.map { $0.id }, Self.pixelArtCreatureIDs)
        XCTAssertNil(PetArtCatalog.creature(id: "cat"))
        XCTAssertNil(PetArtCatalog.creature(id: "no-such-creature"))
    }

    func testEveryPixelArtCreatureHasValidFullStageCoverage() throws {
        for id in Self.pixelArtCreatureIDs {
            let creature = try XCTUnwrap(PetArtCatalog.creature(id: id), "missing pixel art '\(id)'")
            XCTAssertEqual(creature.stages.count, 6, "creature '\(id)' stage count")

            for (index, stage) in creature.stages.enumerated() {
                XCTAssertEqual(stage.jump.count, 2, "creature '\(id)' stage \(index) jump frame count")
                XCTAssertEqual(stage.sleep.count, 2, "creature '\(id)' stage \(index) sleep frame count")
            }

            let issues = PetArtValidator.issues(
                in: creature,
                palette: PetArtCatalog.validationPalette
            )
            XCTAssertEqual(issues, [], "creature '\(id)' has art issues")
        }
    }

    func testCatalogIdsAreUnique() {
        let visualIds = PetVisualCatalog.all.map { $0.id }
        let pixelArtIds = PetArtCatalog.all.map { $0.id }

        XCTAssertEqual(visualIds.count, Set(visualIds).count, "duplicate visual ids: \(visualIds)")
        XCTAssertEqual(pixelArtIds.count, Set(pixelArtIds).count, "duplicate pixel-art ids: \(pixelArtIds)")
    }
}
