#if os(macOS)

import AppKit
import ClaudeCatCore
import ClaudeCatPet
import XCTest
@testable import ClaudeCatApp

@MainActor
final class CatIllustrationViewTests: XCTestCase {
    func testActiveFramesAdvanceSmoothlyWithoutDuplicateStartOrRedraw() {
        let harness = makeHarness()
        harness.view.update(
            stage: 1,
            family: .sonnet,
            state: .jumping(frameInterval: 1.2),
            overlay: .none
        )
        harness.view.setRunning(true)
        harness.view.setRunning(true)
        harness.resetRedrawCount()

        harness.driver.pulse(timestamp: 101)
        drainMainQueue()
        let first = harness.view.currentSample
        harness.driver.pulse(timestamp: 101.1)
        drainMainQueue()
        let second = harness.view.currentSample

        XCTAssertEqual(harness.driver.startCount, 1)
        XCTAssertEqual(harness.redrawCount, 2)
        XCTAssertNotEqual(first.screenGlow, second.screenGlow)
        XCTAssertNotEqual(first.tailOffset, second.tailOffset)
    }

    func testCadenceChangePreservesPoseAndUsesNewPeriodForLaterFrames() {
        let harness = makeHarness()
        harness.view.update(
            stage: 1,
            family: .sonnet,
            state: .jumping(frameInterval: 1.8),
            overlay: .none
        )
        harness.view.setRunning(true)
        harness.clock.now = 101
        harness.driver.pulse(timestamp: 101)
        drainMainQueue()
        let beforeCadenceChange = harness.view.currentSample

        harness.view.update(
            stage: 1,
            family: .sonnet,
            state: .jumping(frameInterval: 0.7),
            overlay: .none
        )
        let afterCadenceChange = harness.view.currentSample
        assertContinuousMotion(beforeCadenceChange, afterCadenceChange)
        XCTAssertEqual(harness.driver.startCount, 1)

        harness.clock.now = 101.1
        harness.driver.pulse(timestamp: 101.1)
        drainMainQueue()
        XCTAssertNotEqual(
            harness.view.currentSample.headOffsetX,
            afterCadenceChange.headOffsetX
        )
    }

    func testStopBrokenDragAndDeinitRejectStalePulsesAndRestartCleanly() {
        let driver = ManualCatDisplayLinkDriver()
        let clock = ManualCatClock(now: 100)
        var redrawCount = 0
        var view: CatIllustrationView? = CatIllustrationView(
            frame: NSRect(x: 0, y: 0, width: 128, height: 128),
            frameDriver: driver,
            monotonicClock: { clock.now },
            reduceMotionProvider: { false }
        )
        view?.onRedrawRequested = { redrawCount += 1 }
        view?.update(
            stage: 2,
            family: .opus,
            state: .jumping(frameInterval: 1),
            overlay: .none
        )
        view?.setRunning(true)
        redrawCount = 0
        let beforeStop = view?.currentSample

        driver.pulse(timestamp: 101)
        view?.setRunning(false)
        drainMainQueue()
        XCTAssertEqual(redrawCount, 1)
        XCTAssertEqual(driver.stopCount, 1)

        view?.setRunning(true)
        XCTAssertEqual(driver.startCount, 2)
        XCTAssertEqual(view?.currentSample, beforeStop)
        redrawCount = 0
        driver.pulse(timestamp: 102)
        drainMainQueue()
        XCTAssertEqual(redrawCount, 1)

        view?.update(
            stage: 2,
            family: .opus,
            state: .broken,
            overlay: .none
        )
        XCTAssertEqual(driver.stopCount, 2)
        redrawCount = 0
        driver.pulse(timestamp: 103)
        drainMainQueue()
        XCTAssertEqual(redrawCount, 0)

        view?.update(
            stage: 2,
            family: .opus,
            state: .jumping(frameInterval: 1),
            overlay: .none
        )
        XCTAssertEqual(driver.startCount, 3)
        view?.update(
            stage: 2,
            family: .opus,
            state: .jumping(frameInterval: 1),
            overlay: .dragging
        )
        XCTAssertEqual(driver.stopCount, 3)
        redrawCount = 0
        driver.pulse(timestamp: 104)
        drainMainQueue()
        XCTAssertEqual(redrawCount, 0)

        weak var weakView = view
        view = nil
        XCTAssertNil(weakView)
        driver.pulse(timestamp: 105)
        drainMainQueue()
        XCTAssertEqual(redrawCount, 0)
    }

    func testUpdatesChangeStageAccentAndOverlayInPlace() {
        let harness = makeHarness()
        let identity = ObjectIdentifier(harness.view)

        harness.view.update(
            stage: 1,
            family: .sonnet,
            state: .jumping(frameInterval: 1),
            overlay: .hovering
        )
        let small = harness.view.currentSample
        harness.view.update(
            stage: 5,
            family: .haiku,
            state: .jumping(frameInterval: 1),
            overlay: .startled
        )
        let large = harness.view.currentSample

        XCTAssertEqual(ObjectIdentifier(harness.view), identity)
        XCTAssertEqual(small.clampedStage, 1)
        XCTAssertEqual(small.pose, .hovering)
        XCTAssertEqual(small.accent, PetPalette.accentColor(for: .sonnet))
        XCTAssertEqual(large.clampedStage, 5)
        XCTAssertEqual(large.pose, .startled)
        XCTAssertEqual(large.accent, PetPalette.accentColor(for: .haiku))
        XCTAssertGreaterThan(large.bodyScale, small.bodyScale)
    }

    func testReducedMotionStopsAndRestartsWithoutLosingStateOrPhase() {
        let driver = ManualCatDisplayLinkDriver()
        let clock = ManualCatClock(now: 20)
        let motion = ManualReduceMotion(isEnabled: false)
        let view = CatIllustrationView(
            frame: NSRect(x: 0, y: 0, width: 128, height: 128),
            frameDriver: driver,
            monotonicClock: { clock.now },
            reduceMotionProvider: { motion.isEnabled }
        )
        view.update(
            stage: 4,
            family: .fable,
            state: .jumping(frameInterval: 0.7),
            overlay: .hovering
        )
        view.setRunning(true)
        clock.now = 21
        driver.pulse(timestamp: 21)
        drainMainQueue()
        let animated = view.currentSample

        motion.isEnabled = true
        view.update(
            stage: 4,
            family: .fable,
            state: .jumping(frameInterval: 0.7),
            overlay: .hovering
        )
        let reduced = view.currentSample
        driver.pulse(timestamp: 22)
        drainMainQueue()

        XCTAssertEqual(driver.startCount, 1)
        XCTAssertEqual(driver.stopCount, 1)
        XCTAssertEqual(view.currentSample, reduced)
        XCTAssertEqual(reduced.clampedStage, 4)
        XCTAssertEqual(reduced.pose, .hovering)
        XCTAssertEqual(reduced.accent, PetPalette.accentColor(for: .fable))
        XCTAssertFalse(reduced.decorativeMotionEnabled)

        motion.isEnabled = false
        clock.now = 22
        view.update(
            stage: 4,
            family: .fable,
            state: .jumping(frameInterval: 0.7),
            overlay: .hovering
        )
        XCTAssertEqual(driver.startCount, 2)
        assertContinuousMotion(animated, view.currentSample)
        XCTAssertTrue(view.currentSample.decorativeMotionEnabled)
    }

    func testFailedDriverStartCanRetryWithoutAcceptingFailedPulses() {
        let harness = makeHarness()
        harness.driver.shouldFailNextStart = true
        harness.view.update(
            stage: 1,
            family: .sonnet,
            state: .jumping(frameInterval: 1),
            overlay: .none
        )
        harness.view.setRunning(true)
        harness.resetRedrawCount()

        harness.driver.pulse(timestamp: 101)
        drainMainQueue()
        XCTAssertEqual(harness.driver.startAttemptCount, 1)
        XCTAssertEqual(harness.driver.startCount, 0)
        XCTAssertEqual(harness.redrawCount, 0)

        harness.view.setRunning(true)
        harness.resetRedrawCount()
        harness.driver.pulse(timestamp: 101)
        drainMainQueue()
        XCTAssertEqual(harness.driver.startAttemptCount, 2)
        XCTAssertEqual(harness.driver.startCount, 1)
        XCTAssertEqual(harness.redrawCount, 1)
    }

    func testActiveViewDeinitStopsDriverAndClearsCallback() {
        let driver = ManualCatDisplayLinkDriver()
        let clock = ManualCatClock(now: 10)
        var view: CatIllustrationView? = CatIllustrationView(
            frame: NSRect(x: 0, y: 0, width: 128, height: 128),
            frameDriver: driver,
            monotonicClock: { clock.now },
            reduceMotionProvider: { false }
        )
        view?.update(
            stage: 0,
            family: nil,
            state: .jumping(frameInterval: 1),
            overlay: .none
        )
        view?.setRunning(true)

        weak var weakView = view
        view = nil

        XCTAssertNil(weakView)
        XCTAssertEqual(driver.stopCount, 1)
        XCTAssertNil(driver.timestampHandler)
    }

    func testBurstCallbacksCoalesceToOnePendingMainRedraw() {
        let harness = makeHarness()
        harness.view.update(
            stage: 0,
            family: nil,
            state: .jumping(frameInterval: 1),
            overlay: .none
        )
        harness.view.setRunning(true)
        harness.resetRedrawCount()

        harness.driver.pulse(timestamp: 101)
        harness.driver.pulse(timestamp: 101.01)
        harness.driver.pulse(timestamp: 101.02)
        XCTAssertEqual(harness.redrawCount, 0)
        drainMainQueue()

        XCTAssertEqual(harness.redrawCount, 1)
    }

    private func makeHarness() -> CatViewHarness {
        CatViewHarness()
    }

    private func drainMainQueue() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

    private func assertContinuousMotion(
        _ left: CatAnimationSample,
        _ right: CatAnimationSample,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let leftValues = motionValues(left)
        let rightValues = motionValues(right)
        XCTAssertEqual(leftValues.count, rightValues.count, file: file, line: line)
        for (leftValue, rightValue) in zip(leftValues, rightValues) {
            XCTAssertEqual(
                leftValue,
                rightValue,
                accuracy: 0.000_001,
                file: file,
                line: line
            )
        }
    }

    private func motionValues(_ sample: CatAnimationSample) -> [Double] {
        [
            sample.bodyBreath,
            sample.headOffsetX,
            sample.headOffsetY,
            sample.eyeOffsetX,
            sample.eyeOffsetY,
            sample.earOffset,
            sample.tailOffset,
            sample.leftPawOffsetX,
            sample.leftPawOffsetY,
            sample.rightPawOffsetX,
            sample.rightPawOffsetY,
            sample.blinkAmount,
            sample.screenGlow
        ]
    }
}

@MainActor
private final class CatViewHarness {
    let driver = ManualCatDisplayLinkDriver()
    let clock = ManualCatClock(now: 100)
    let view: CatIllustrationView
    private(set) var redrawCount = 0

    init() {
        view = CatIllustrationView(
            frame: NSRect(x: 0, y: 0, width: 128, height: 128),
            frameDriver: driver,
            monotonicClock: { [clock] in clock.now },
            reduceMotionProvider: { false }
        )
        view.onRedrawRequested = { [weak self] in
            self?.redrawCount += 1
        }
    }

    func resetRedrawCount() {
        redrawCount = 0
    }
}

private final class ManualCatClock {
    var now: TimeInterval

    init(now: TimeInterval) {
        self.now = now
    }
}

private final class ManualReduceMotion {
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}

private final class ManualCatDisplayLinkDriver: CatDisplayLinkDriving {
    var timestampHandler: (@Sendable (TimeInterval) -> Void)?
    var shouldFailNextStart = false
    private(set) var startAttemptCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var isRunning = false

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        startAttemptCount += 1
        if shouldFailNextStart {
            shouldFailNextStart = false
            return false
        }
        isRunning = true
        startCount += 1
        return true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopCount += 1
    }

    func pulse(timestamp: TimeInterval) {
        timestampHandler?(timestamp)
    }
}

#endif
