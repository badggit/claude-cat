import Foundation
import XCTest
import ClaudeCatPet

final class CatAnimationPlannerTests: XCTestCase {
    private let accent = PetColor(r: 52, g: 120, b: 246, a: 255)
    private let activeBehavior = PetBehaviorState.jumping(frameInterval: 0.5)

    func testStagesClampToTheValidRangeAndStayActive() {
        let expected: [(stage: Int, clamped: Int)] = [
            (-4, 0),
            (0, 0),
            (1, 1),
            (2, 2),
            (3, 3),
            (4, 4),
            (5, 5),
            (11, 5)
        ]

        for item in expected {
            let sample = makeSample(stage: item.stage)
            XCTAssertEqual(sample.clampedStage, item.clamped, "stage \(item.stage)")
            XCTAssertEqual(sample.pose, .active, "stage \(item.stage)")
        }
    }

    func testTypingCycleAlternatesPawsAndKeepsGlowBounded() {
        let period = CatAnimationPlanner.period(behavior: activeBehavior)
        let leftContact = makeSample(stage: 1, elapsed: period / 32)
        let rightContact = makeSample(stage: 1, elapsed: period * 3 / 32)

        XCTAssertGreaterThan(leftContact.leftPawOffsetY, leftContact.rightPawOffsetY)
        XCTAssertGreaterThan(rightContact.rightPawOffsetY, rightContact.leftPawOffsetY)
        XCTAssertGreaterThan(leftContact.leftPawOffsetY, 0)
        XCTAssertEqual(leftContact.rightPawOffsetY, 0, accuracy: 0.000_000_001)
        XCTAssertGreaterThan(rightContact.rightPawOffsetY, 0)
        XCTAssertEqual(rightContact.leftPawOffsetY, 0, accuracy: 0.000_000_001)
        // The alternation is symmetric: each paw presses to the same depth.
        XCTAssertEqual(
            leftContact.leftPawOffsetY,
            rightContact.rightPawOffsetY,
            accuracy: 0.000_000_001
        )

        for sample in [leftContact, rightContact] {
            XCTAssertGreaterThanOrEqual(sample.screenGlow, 0)
            XCTAssertLessThanOrEqual(sample.screenGlow, 1)
        }
    }

    func testScreenGlowTracksTheBehaviorState() {
        let active = makeSample(stage: 1)
        let sleeping = makeSample(stage: 1, behavior: .sleeping)
        let broken = makeSample(stage: 1, behavior: .broken)

        XCTAssertGreaterThan(active.screenGlow, sleeping.screenGlow)
        XCTAssertGreaterThan(sleeping.screenGlow, broken.screenGlow)
        XCTAssertEqual(broken.screenGlow, 0, accuracy: 0.000_000_001)
    }

    func testBrokenSleepAndReducedMotionHonorPrecedenceAndStayCalm() {
        let broken = CatAnimationPlanner.sample(
            stage: 2,
            behavior: .broken,
            overlay: .startled,
            elapsed: 7,
            accent: accent,
            reduceMotion: false
        )
        XCTAssertEqual(broken.pose, .broken)
        XCTAssertEqual(broken.desaturation, 1)
        XCTAssertEqual(broken.screenGlow, 0, accuracy: 0.000_000_001)
        XCTAssertFalse(broken.decorativeMotionEnabled)
        XCTAssertNotEqual(broken.accent, accent)

        let brokenLater = CatAnimationPlanner.sample(
            stage: 2,
            behavior: .broken,
            overlay: .startled,
            elapsed: 41,
            accent: accent,
            reduceMotion: false
        )
        XCTAssertEqual(broken, brokenLater)

        let sleeping = CatAnimationPlanner.sample(
            stage: 2,
            behavior: .sleeping,
            overlay: .none,
            elapsed: 3,
            accent: accent,
            reduceMotion: false
        )
        XCTAssertEqual(sleeping.pose, .sleeping)
        XCTAssertEqual(sleeping.blinkAmount, 1, accuracy: 0.000_000_001)
        XCTAssertLessThanOrEqual(abs(sleeping.bodyBreath), 0.012)
        XCTAssertLessThanOrEqual(abs(sleeping.tailOffset), 0.5)
        XCTAssertLessThanOrEqual(sleeping.screenGlow, 0.2)

        let reducedEarly = makeSample(stage: 2, overlay: .hovering, elapsed: 1, reduceMotion: true)
        let reducedLate = makeSample(stage: 2, overlay: .hovering, elapsed: 99, reduceMotion: true)
        XCTAssertFalse(reducedEarly.decorativeMotionEnabled)
        XCTAssertEqual(reducedEarly, reducedLate)
        XCTAssertEqual(reducedEarly.pose, .hovering)
    }

    func testPointerReactionsAreDistinctAndDraggingIsStable() {
        let active = makeSample(stage: 1)
        let hover = makeSample(stage: 1, overlay: .hovering)
        let startled = makeSample(stage: 1, overlay: .startled)
        let draggingEarly = makeSample(stage: 1, overlay: .dragging, elapsed: 1)
        let draggingLate = makeSample(stage: 1, overlay: .dragging, elapsed: 25)

        XCTAssertEqual(active.pose, .active)
        XCTAssertEqual(hover.pose, .hovering)
        XCTAssertEqual(startled.pose, .startled)
        XCTAssertEqual(draggingEarly.pose, .dragging)

        XCTAssertNotEqual(active.headOffsetY, hover.headOffsetY)
        XCTAssertNotEqual(hover.headOffsetY, startled.headOffsetY)
        // Hover and click both lift the paws off the keyboard; click flings
        // them highest and brightens the screen the most.
        XCTAssertLessThan(hover.leftPawOffsetY, active.leftPawOffsetY)
        XCTAssertLessThan(startled.leftPawOffsetY, hover.leftPawOffsetY)
        XCTAssertGreaterThan(startled.screenGlow, active.screenGlow)
        XCTAssertEqual(draggingEarly, draggingLate)
        XCTAssertFalse(draggingEarly.decorativeMotionEnabled)
    }

    // Sleep must not swallow the pointer: an idle cat is still grabbable and
    // still notices the cursor, exactly like the pixel creatures.
    func testSleepingCatStillReactsToThePointer() {
        let idle = makeSample(stage: 2, behavior: .sleeping)
        let hover = makeSample(stage: 2, behavior: .sleeping, overlay: .hovering)
        let startled = makeSample(stage: 2, behavior: .sleeping, overlay: .startled)
        let dragging = makeSample(stage: 2, behavior: .sleeping, overlay: .dragging)

        XCTAssertEqual(idle.pose, .sleeping)
        XCTAssertEqual(hover.pose, .hovering)
        XCTAssertEqual(startled.pose, .startled)
        XCTAssertEqual(dragging.pose, .dragging)

        // A hovered sleeper opens its eyes, lifts its head out of the nap pose,
        // and wakes its laptop screen.
        XCTAssertLessThan(hover.blinkAmount, idle.blinkAmount)
        XCTAssertGreaterThan(hover.headOffsetY, idle.headOffsetY)
        XCTAssertGreaterThan(hover.screenGlow, idle.screenGlow)
        // Being carried is a still pose, so the drag frame never animates.
        XCTAssertFalse(dragging.decorativeMotionEnabled)
        XCTAssertEqual(
            dragging,
            makeSample(stage: 2, behavior: .sleeping, overlay: .dragging, elapsed: 25)
        )
    }

    func testScaleGeometryAndFullPeriodRemainSafeAndPeriodic() {
        let scales = (0...5).map { makeSample(stage: $0).bodyScale }
        for index in 1..<scales.count {
            XCTAssertGreaterThan(scales[index], scales[index - 1])
        }
        XCTAssertLessThanOrEqual(scales.last ?? 2, 1.12)

        let period = CatAnimationPlanner.period(behavior: activeBehavior)
        for stage in 0...5 {
            for step in 0...32 {
                let sample = makeSample(stage: stage, elapsed: period * Double(step) / 32)
                assertGeometryIsSafe(sample)
            }

            let start = makeSample(stage: stage, elapsed: 0)
            let repeated = makeSample(stage: stage, elapsed: period)
            assertSamplesEqual(start, repeated, accuracy: 0.000_000_001)
        }
    }

    func testEveryPoseStaysWithinSafeGeometryBounds() {
        let overlays: [PetOverlay] = [.none, .hovering, .startled, .dragging]
        let behaviors: [PetBehaviorState] = [activeBehavior, .sleeping, .broken]
        for behavior in behaviors {
            for overlay in overlays {
                for step in 0...8 {
                    let sample = CatAnimationPlanner.sample(
                        stage: 3,
                        behavior: behavior,
                        overlay: overlay,
                        elapsed: Double(step) * 1.7,
                        accent: accent,
                        reduceMotion: false
                    )
                    assertGeometryIsSafe(sample)
                }
            }
        }
    }

    func testActivityCadenceUsesTheDesktopPetIntervalRange() {
        let fastest = CatAnimationPlanner.period(behavior: .jumping(frameInterval: 0.7))
        let middle = CatAnimationPlanner.period(behavior: .jumping(frameInterval: 1.6))
        let slowest = CatAnimationPlanner.period(behavior: .jumping(frameInterval: 2.5))
        let belowRange = CatAnimationPlanner.period(behavior: .jumping(frameInterval: 0.1))
        let aboveRange = CatAnimationPlanner.period(behavior: .jumping(frameInterval: 10))

        XCTAssertLessThan(fastest, middle)
        XCTAssertLessThan(middle, slowest)
        XCTAssertEqual(belowRange, fastest, accuracy: 0.000_001)
        XCTAssertEqual(aboveRange, slowest, accuracy: 0.000_001)
    }

    private func makeSample(
        stage: Int,
        behavior: PetBehaviorState? = nil,
        overlay: PetOverlay = .none,
        elapsed: TimeInterval = 0,
        reduceMotion: Bool = false
    ) -> CatAnimationSample {
        CatAnimationPlanner.sample(
            stage: stage,
            behavior: behavior ?? activeBehavior,
            overlay: overlay,
            elapsed: elapsed,
            accent: accent,
            reduceMotion: reduceMotion
        )
    }

    private func assertGeometryIsSafe(
        _ sample: CatAnimationSample,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(abs(sample.bodyBreath), 0.015, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(sample.headOffsetX), 1.5, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(sample.headOffsetY), 1.5, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(sample.eyeOffsetX), 1.0, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(sample.eyeOffsetY), 0.75, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(sample.earOffset), 1.0, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(sample.tailOffset), 2.5, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(sample.leftPawOffsetX), 2.5, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(sample.leftPawOffsetY), 2.5, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(sample.rightPawOffsetX), 2.5, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(sample.rightPawOffsetY), 2.5, file: file, line: line)
        XCTAssertGreaterThanOrEqual(sample.screenGlow, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(sample.screenGlow, 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(sample.blinkAmount, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(sample.blinkAmount, 1, file: file, line: line)
    }

    private func assertSamplesEqual(
        _ left: CatAnimationSample,
        _ right: CatAnimationSample,
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(left.clampedStage, right.clampedStage, file: file, line: line)
        XCTAssertEqual(left.pose, right.pose, file: file, line: line)
        XCTAssertEqual(left.bodyScale, right.bodyScale, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.bodyRoundness, right.bodyRoundness, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.bodyBreath, right.bodyBreath, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.headOffsetX, right.headOffsetX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.headOffsetY, right.headOffsetY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.eyeOffsetX, right.eyeOffsetX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.eyeOffsetY, right.eyeOffsetY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.earOffset, right.earOffset, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.tailOffset, right.tailOffset, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.leftPawOffsetX, right.leftPawOffsetX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.leftPawOffsetY, right.leftPawOffsetY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.rightPawOffsetX, right.rightPawOffsetX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.rightPawOffsetY, right.rightPawOffsetY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.blinkAmount, right.blinkAmount, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.screenGlow, right.screenGlow, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.accent, right.accent, file: file, line: line)
        XCTAssertEqual(left.desaturation, right.desaturation, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(left.decorativeMotionEnabled, right.decorativeMotionEnabled, file: file, line: line)
    }
}
