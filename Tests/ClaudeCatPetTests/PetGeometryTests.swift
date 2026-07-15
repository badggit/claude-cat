import Foundation
import XCTest
import ClaudeCatPet
// CGRect helper accessors come from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class PetGeometryTests: XCTestCase {
    // AppKit-style visible frames (y grows upward): a main laptop screen
    // plus a secondary display arranged to its right.
    private let mainFrame = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let secondaryFrame = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    private let petSize = CGSize(width: 96, height: 96)
    private let margin: CGFloat = 24

    private func sanitized(_ saved: CGPoint?, screens: [CGRect]) -> CGPoint {
        PetGeometry.sanitizedOrigin(saved: saved,
                                    petSize: petSize,
                                    screenVisibleFrames: screens,
                                    mainVisibleFrame: mainFrame,
                                    margin: margin)
    }

    // MARK: - defaultOrigin(mainVisibleFrame:petSize:margin:)

    func testDefaultOriginIsBottomRightOfMainFrameInsetByMargin() {
        let origin = PetGeometry.defaultOrigin(mainVisibleFrame: mainFrame,
                                               petSize: petSize,
                                               margin: margin)
        XCTAssertEqual(origin, CGPoint(x: 1440 - 24 - 96, y: 24))
    }

    // MARK: - sanitizedOrigin(saved:petSize:screenVisibleFrames:mainVisibleFrame:margin:)

    func testNilSavedFallsBackToBottomRightDefault() {
        XCTAssertEqual(sanitized(nil, screens: [mainFrame, secondaryFrame]),
                       CGPoint(x: 1320, y: 24))
    }

    func testSavedInsideSecondaryScreenIsKeptUnchanged() {
        let saved = CGPoint(x: 2000, y: 500)
        XCTAssertEqual(sanitized(saved, screens: [mainFrame, secondaryFrame]), saved)
    }

    func testSavedFarOffAllScreensIsClampedFullyInsideMain() {
        let clamped = sanitized(CGPoint(x: 5000, y: 5000),
                                screens: [mainFrame, secondaryFrame])
        XCTAssertEqual(clamped, CGPoint(x: 1440 - 96, y: 875 - 96))
        XCTAssertTrue(mainFrame.contains(CGRect(origin: clamped, size: petSize)),
                      "pet rect must land fully inside the main frame")
    }

    func testSavedFarBelowLeftIsClampedToMainLowerLeftCorner() {
        let clamped = sanitized(CGPoint(x: -5000, y: -5000),
                                screens: [mainFrame, secondaryFrame])
        XCTAssertEqual(clamped, CGPoint(x: 0, y: 0))
    }

    // Overlap one point short of minVisibleEdge in a single dimension
    // counts as off-screen even though the other dimension overlaps fully.
    func testOverlapBelowMinVisibleEdgeInOneDimensionIsClamped() {
        let saved = CGPoint(x: PetGeometry.minVisibleEdge - petSize.width - 1, y: 100)
        XCTAssertEqual(sanitized(saved, screens: [mainFrame]),
                       CGPoint(x: 0, y: 100))
    }

    func testOverlapExactlyMinVisibleEdgeCountsAsVisible() {
        let saved = CGPoint(x: PetGeometry.minVisibleEdge - petSize.width, y: 100)
        XCTAssertEqual(sanitized(saved, screens: [mainFrame]), saved)
    }

    func testEmptyScreenListClampsIntoMain() {
        let clamped = sanitized(CGPoint(x: 2000, y: 500), screens: [])
        XCTAssertEqual(clamped, CGPoint(x: 1440 - 96, y: 500))
        XCTAssertTrue(mainFrame.contains(CGRect(origin: clamped, size: petSize)),
                      "pet rect must land fully inside the main frame")
    }

    // MARK: - minVisibleEdge

    func testMinVisibleEdgeIsPinnedAtThirtyTwoPoints() {
        XCTAssertEqual(PetGeometry.minVisibleEdge, 32)
    }
}
