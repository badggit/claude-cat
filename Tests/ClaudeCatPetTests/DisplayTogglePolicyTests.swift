import Foundation
import XCTest
import ClaudeCatPet

final class DisplayTogglePolicyTests: XCTestCase {
    private let bothDisplays: [PetDisplay] = [.menuBar, .pet]

    private let allStates: [DisplayFlags] = [
        DisplayFlags(menuBar: true, pet: true),
        DisplayFlags(menuBar: true, pet: false),
        DisplayFlags(menuBar: false, pet: true),
        DisplayFlags(menuBar: false, pet: false)
    ]

    private let legalStates: [DisplayFlags] = [
        DisplayFlags(menuBar: true, pet: true),
        DisplayFlags(menuBar: true, pet: false),
        DisplayFlags(menuBar: false, pet: true)
    ]

    // MARK: - toggling(_:_:)

    func testTogglingPetOffWhileBothOnDisablesOnlyPet() {
        XCTAssertEqual(DisplayTogglePolicy.toggling(.bothOn, .pet),
                       DisplayFlags(menuBar: true, pet: false))
    }

    func testTogglingMenuBarOffWhileBothOnDisablesOnlyMenuBar() {
        XCTAssertEqual(DisplayTogglePolicy.toggling(.bothOn, .menuBar),
                       DisplayFlags(menuBar: false, pet: true))
    }

    func testTogglingLastEnabledMenuBarOffReturnsFlagsUnchanged() {
        let onlyMenuBar = DisplayFlags(menuBar: true, pet: false)
        XCTAssertEqual(DisplayTogglePolicy.toggling(onlyMenuBar, .menuBar), onlyMenuBar)
    }

    func testTogglingLastEnabledPetOffReturnsFlagsUnchanged() {
        let onlyPet = DisplayFlags(menuBar: false, pet: true)
        XCTAssertEqual(DisplayTogglePolicy.toggling(onlyPet, .pet), onlyPet)
    }

    // The invariant must hold across every single-step transition
    // from all four flag states: no toggle may produce both-off.
    func testNoSingleStepTransitionEverProducesBothOff() {
        for flags in allStates {
            for display in bothDisplays {
                let next = DisplayTogglePolicy.toggling(flags, display)
                XCTAssertTrue(next.menuBar || next.pet,
                              "toggling \(display) on \(flags) produced both-off")
            }
        }
    }

    func testEnablingDisabledDisplayIsAlwaysAllowedRegardlessOfOtherFlag() {
        for other in [true, false] {
            XCTAssertEqual(DisplayTogglePolicy.toggling(DisplayFlags(menuBar: false, pet: other), .menuBar),
                           DisplayFlags(menuBar: true, pet: other))
            XCTAssertEqual(DisplayTogglePolicy.toggling(DisplayFlags(menuBar: other, pet: false), .pet),
                           DisplayFlags(menuBar: other, pet: true))
        }
    }

    // MARK: - canDisable(_:_:)

    func testCanDisableIsFalseExactlyForLastEnabledDisplay() {
        XCTAssertFalse(DisplayTogglePolicy.canDisable(DisplayFlags(menuBar: true, pet: false), .menuBar))
        XCTAssertFalse(DisplayTogglePolicy.canDisable(DisplayFlags(menuBar: false, pet: true), .pet))
    }

    func testCanDisableIsTrueWhenOtherDisplayIsOn() {
        XCTAssertTrue(DisplayTogglePolicy.canDisable(.bothOn, .menuBar))
        XCTAssertTrue(DisplayTogglePolicy.canDisable(.bothOn, .pet))
    }

    // canDisable must agree with toggling: a disable attempt is a no-op
    // exactly when canDisable reports false for an enabled display.
    func testCanDisableMatchesTogglingAcrossLegalStates() {
        for flags in legalStates {
            for display in bothDisplays {
                let enabled = display == .menuBar ? flags.menuBar : flags.pet
                guard enabled else { continue }
                let blocked = DisplayTogglePolicy.toggling(flags, display) == flags
                XCTAssertEqual(blocked, !DisplayTogglePolicy.canDisable(flags, display),
                               "canDisable disagrees with toggling for \(display) on \(flags)")
            }
        }
    }

    // MARK: - sanitized(_:)

    func testSanitizedBothOffForcesMenuBarOn() {
        XCTAssertEqual(DisplayTogglePolicy.sanitized(DisplayFlags(menuBar: false, pet: false)),
                       DisplayFlags(menuBar: true, pet: false))
    }

    func testSanitizedPassesLegalStatesThroughUnchanged() {
        for flags in legalStates {
            XCTAssertEqual(DisplayTogglePolicy.sanitized(flags), flags)
        }
    }

    // MARK: - module hygiene

    // ClaudeCatPet must stay AppKit-free so it builds and tests on Linux;
    // scan the module's sources instead of trusting compilation on macOS.
    func testModuleSourcesDoNotImportAppKit() throws {
        let sourcesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/ClaudeCatPetTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Sources/ClaudeCatPet", isDirectory: true)
        var swiftFiles: [URL] = []
        let enumerator = FileManager.default.enumerator(at: sourcesDir,
                                                        includingPropertiesForKeys: nil)
        while let entry = enumerator?.nextObject() as? URL {
            if entry.pathExtension == "swift" {
                swiftFiles.append(entry)
            }
        }
        XCTAssertFalse(swiftFiles.isEmpty, "module sources not found at \(sourcesDir.path)")
        // Cocoa re-exports AppKit and SwiftUI drags in platform UI; ban all three.
        let bannedImports = ["import AppKit", "import Cocoa", "import SwiftUI"]
        for file in swiftFiles {
            let text = try String(contentsOf: file, encoding: .utf8)
            for banned in bannedImports {
                XCTAssertFalse(text.contains(banned),
                               "\(file.lastPathComponent) must not contain '\(banned)'")
            }
        }
    }
}
