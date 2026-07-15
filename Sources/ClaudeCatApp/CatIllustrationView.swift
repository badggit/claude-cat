#if os(macOS)

import AppKit
import ClaudeCatCore
import ClaudeCatPet
import Foundation

// The display thread reserves work here before handing AppKit work to main.
private final class CatFrameDeliveryGate: @unchecked Sendable {
    private let lock = NSLock()
    private var activeGeneration: UInt64?
    private var nextGeneration: UInt64 = 1
    private var hasPendingDelivery = false

    func activate() -> UInt64 {
        lock.lock()
        let generation = nextGeneration
        nextGeneration &+= 1
        activeGeneration = generation
        hasPendingDelivery = false
        lock.unlock()
        return generation
    }

    func invalidate() {
        lock.lock()
        activeGeneration = nil
        hasPendingDelivery = false
        lock.unlock()
    }

    func reserve(generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard activeGeneration == generation, !hasPendingDelivery else {
            return false
        }
        hasPendingDelivery = true
        return true
    }

    func consume(generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard activeGeneration == generation, hasPendingDelivery else {
            return false
        }
        hasPendingDelivery = false
        return true
    }
}

final class CatIllustrationView: NSView {
    private(set) var currentSample: CatAnimationSample
    var onRedrawRequested: (() -> Void)?

    private let frameDriver: CatDisplayLinkDriving
    private let monotonicClock: () -> TimeInterval
    private let reduceMotionProvider: () -> Bool
    private let deliveryGate = CatFrameDeliveryGate()

    private var stage = 0
    private var family: ModelFamily?
    private var behavior: PetBehaviorState = .sleeping
    private var overlay: PetOverlay = .none
    private var reduceMotionEnabled: Bool

    private var shouldRun = false
    private var isDriverRunning = false
    // Normalized cycles preserve the visible pose when cadence changes.
    private var phaseCycles = 0.0
    private var lastPhaseTimestamp: TimeInterval?

    override init(frame frameRect: NSRect) {
        let reduceMotion = NSWorkspace.shared
            .accessibilityDisplayShouldReduceMotion
        frameDriver = CatDisplayLinkDriver()
        monotonicClock = { CatDisplayLinkClock.now() }
        reduceMotionProvider = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        reduceMotionEnabled = reduceMotion
        currentSample = Self.makeInitialSample(reduceMotion: reduceMotion)
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        let reduceMotion = NSWorkspace.shared
            .accessibilityDisplayShouldReduceMotion
        frameDriver = CatDisplayLinkDriver()
        monotonicClock = { CatDisplayLinkClock.now() }
        reduceMotionProvider = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        reduceMotionEnabled = reduceMotion
        currentSample = Self.makeInitialSample(reduceMotion: reduceMotion)
        super.init(coder: coder)
    }

    init(
        frame frameRect: NSRect,
        frameDriver: CatDisplayLinkDriving,
        monotonicClock: @escaping () -> TimeInterval,
        reduceMotionProvider: @escaping () -> Bool
    ) {
        let reduceMotion = reduceMotionProvider()
        self.frameDriver = frameDriver
        self.monotonicClock = monotonicClock
        self.reduceMotionProvider = reduceMotionProvider
        reduceMotionEnabled = reduceMotion
        currentSample = Self.makeInitialSample(reduceMotion: reduceMotion)
        super.init(frame: frameRect)
    }

    deinit {
        deliveryGate.invalidate()
        frameDriver.timestampHandler = nil
        if isDriverRunning {
            frameDriver.stop()
        }
    }

    override var isOpaque: Bool {
        false
    }

    func update(
        stage: Int,
        family: ModelFamily?,
        state: PetBehaviorState,
        overlay: PetOverlay
    ) {
        precondition(Thread.isMainThread)
        advancePhaseToCurrentClock()
        self.stage = stage
        self.family = family
        behavior = state
        self.overlay = overlay
        reduceMotionEnabled = reduceMotionProvider()
        reconcileDriverLifecycle()
        refreshSample()
        requestRedraw()
    }

    func setRunning(_ running: Bool) {
        precondition(Thread.isMainThread)
        advancePhaseToCurrentClock()
        shouldRun = running
        reduceMotionEnabled = reduceMotionProvider()
        reconcileDriverLifecycle()
        refreshSample()
        requestRedraw()
    }

    override func draw(_ dirtyRect: NSRect) {
        precondition(Thread.isMainThread)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        CatIllustrationRenderer.draw(
            sample: currentSample,
            in: bounds,
            context: context
        )
    }

    private static func makeInitialSample(
        reduceMotion: Bool
    ) -> CatAnimationSample {
        CatAnimationPlanner.sample(
            stage: 0,
            behavior: .sleeping,
            overlay: .none,
            elapsed: 0,
            accent: PetPalette.accentColor(for: nil),
            reduceMotion: reduceMotion
        )
    }

    private var presentationNeedsContinuousFrames: Bool {
        guard !reduceMotionEnabled,
              behavior != .broken,
              overlay != .dragging else {
            return false
        }
        return true
    }

    private func reconcileDriverLifecycle() {
        let needsDriver = shouldRun && presentationNeedsContinuousFrames
        if needsDriver, !isDriverRunning {
            startDriver()
        } else if !needsDriver, isDriverRunning {
            stopDriver()
        }
    }

    private func startDriver() {
        let now = validTimestamp(monotonicClock(), fallback: 0)
        lastPhaseTimestamp = now

        let generation = deliveryGate.activate()
        let gate = deliveryGate
        frameDriver.timestampHandler = { [weak self] timestamp in
            guard timestamp.isFinite,
                  gate.reserve(generation: generation) else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard gate.consume(generation: generation) else { return }
                self?.consumeDisplayTimestamp(timestamp)
            }
        }
        guard frameDriver.start() else {
            lastPhaseTimestamp = nil
            deliveryGate.invalidate()
            frameDriver.timestampHandler = nil
            return
        }
        isDriverRunning = true
    }

    private func stopDriver() {
        isDriverRunning = false
        lastPhaseTimestamp = nil
        deliveryGate.invalidate()
        frameDriver.timestampHandler = nil
        frameDriver.stop()
    }

    private func consumeDisplayTimestamp(_ timestamp: TimeInterval) {
        precondition(Thread.isMainThread)
        guard isDriverRunning else { return }

        let currentReduceMotion = reduceMotionProvider()
        if currentReduceMotion != reduceMotionEnabled {
            reduceMotionEnabled = currentReduceMotion
            reconcileDriverLifecycle()
        }
        guard isDriverRunning else {
            refreshSample()
            requestRedraw()
            return
        }

        advancePhase(to: timestamp)
        refreshSample()
        requestRedraw()
    }

    private func advancePhaseToCurrentClock() {
        guard isDriverRunning else { return }
        advancePhase(to: monotonicClock())
    }

    private func advancePhase(to timestamp: TimeInterval) {
        guard let lastPhaseTimestamp else { return }
        let safeTimestamp = validTimestamp(timestamp, fallback: lastPhaseTimestamp)
        let elapsed = max(0, safeTimestamp - lastPhaseTimestamp)
        let period = CatAnimationPlanner.period(behavior: behavior)
        if period.isFinite, period > 0 {
            phaseCycles = (phaseCycles + elapsed / period)
                .truncatingRemainder(dividingBy: 1)
        }
        self.lastPhaseTimestamp = max(lastPhaseTimestamp, safeTimestamp)
    }

    private func validTimestamp(
        _ timestamp: TimeInterval,
        fallback: TimeInterval
    ) -> TimeInterval {
        timestamp.isFinite ? timestamp : fallback
    }

    private func refreshSample() {
        let period = CatAnimationPlanner.period(behavior: behavior)
        let elapsed = period.isFinite && period > 0
            ? phaseCycles * period
            : 0
        currentSample = CatAnimationPlanner.sample(
            stage: stage,
            behavior: behavior,
            overlay: overlay,
            elapsed: elapsed,
            accent: PetPalette.accentColor(for: family),
            reduceMotion: reduceMotionEnabled
        )
    }

    private func requestRedraw() {
        needsDisplay = true
        onRedrawRequested?()
    }
}

#endif
