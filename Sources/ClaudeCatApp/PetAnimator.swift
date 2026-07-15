#if os(macOS)

import AppKit
import ClaudeCatCore
import ClaudeCatPet

// Drives the desktop pet's frame cycling from its behavior state and overlay,
// pulling pre-rendered frames from the shared PetSpriteCache and emitting the
// current frame through onFrame. The window controller owns the panel and
// feeds this animator snapshots plus start/stop signals; the animator owns
// only its timers. Energy budget: repeating timers carry a generous
// tolerance and are recreated only when their interval changes, and
// the animator fully stops (timers invalidated, not paused) whenever the
// controller reports the pet is occluded, the screen is asleep, or hidden.
final class PetAnimator {
    // Firing slack allowed on every timer so the OS can coalesce wake-ups
    // (design energy budget: at least 30% of the interval).
    private static let timerToleranceFraction = 0.3
    // A startled pet flips through jump frames at the menu bar's fastest tempo.
    // PetWindowController owns the reaction duration and clears the overlay.
    private static let startleFrameInterval: TimeInterval = 0.15

    // Emits the frame to display; the window controller binds its image view.
    var onFrame: ((NSImage?) -> Void)?

    private let cache: PetSpriteCache

    // Latest inputs pushed by the window controller (main thread only).
    private var creatureID = ""
    private var family: ModelFamily?
    private var state: PetBehaviorState = .sleeping
    private var overlay: PetOverlay = .none
    private var stage = 0
    // True only while the controller reports the pet is on-screen and visible;
    // when false every timer is invalidated (energy budget full stop).
    private var isRunning = false

    private var frameTimer: Timer?
    private var currentInterval: TimeInterval = 0
    private var frames: [NSImage] = []
    private var frameIndex = 0

    init(cache: PetSpriteCache) {
        self.cache = cache
    }

    deinit {
        frameTimer?.invalidate()
    }

    // Pushes a fresh snapshot of what the pet should be doing. The controller
    // owns transient reaction timing, so this animator renders the exact
    // overlay it receives without creating a second deadline.
    func update(creatureID: String,
                family: ModelFamily?,
                state: PetBehaviorState,
                overlay: PetOverlay,
                stage: Int) {
        self.creatureID = creatureID
        self.family = family
        self.state = state
        self.stage = stage
        self.overlay = overlay
        refresh()
    }

    // Allows or forbids animation. Turning it off invalidates every timer
    // (a full stop, not a pause); turning it on re-derives the current frame
    // and timers from the latest inputs.
    func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        isRunning = running
        if running {
            refresh()
        } else {
            stopFrameTimer()
        }
    }

    // Re-derives the frame source, (re)arms the frame timer only when its
    // interval changed, and renders now.
    private func refresh() {
        guard isRunning else { return }
        let plan = framePlan()
        if let interval = plan.interval {
            startFrameTimer(interval: interval)
        } else {
            stopFrameTimer()
        }
        frames = plan.frames
        renderCurrentFrame()
    }

    // Resolves broken state first, then interaction overlays, to a frame array
    // and optional tick interval. A nil interval means a static presentation.
    private func framePlan() -> (frames: [NSImage], interval: TimeInterval?) {
        if state == .broken {
            return (framesFor(.broken), nil)
        }
        if overlay == .dragging {
            return (framesFor(.drag), nil)
        }
        if overlay == .startled {
            return (framesFor(.jump), Self.startleFrameInterval)
        }
        if overlay == .hovering {
            return (framesFor(.hover), nil)
        }
        switch state {
        case .broken:
            return (framesFor(.broken), nil)
        case .sleeping:
            return (framesFor(.sleep), PetStateEngine.sleepFrameInterval)
        case .jumping(let interval):
            return (framesFor(.jump), interval)
        }
    }

    private func framesFor(_ spriteState: PetSpriteState) -> [NSImage] {
        cache.frames(creatureID: creatureID, stage: stage, state: spriteState, family: family)
    }

    // Mirrors StatusItemController.startAnimation: the repeating timer is only
    // recreated when the interval actually changes, so steady usage never
    // restarts the cycle; tolerance stays at 30% of the interval.
    private func startFrameTimer(interval: TimeInterval) {
        if frameTimer != nil, abs(interval - currentInterval) < 0.001 {
            return
        }
        frameTimer?.invalidate()
        currentInterval = interval
        let timer = Timer.scheduledTimer(withTimeInterval: interval,
                                         repeats: true) { [weak self] _ in
            self?.advanceFrame()
        }
        timer.tolerance = interval * Self.timerToleranceFraction
        frameTimer = timer
    }

    private func stopFrameTimer() {
        frameTimer?.invalidate()
        frameTimer = nil
        currentInterval = 0
        frameIndex = 0
    }

    private func advanceFrame() {
        frameIndex &+= 1
        renderCurrentFrame()
    }

    private func renderCurrentFrame() {
        guard !frames.isEmpty else {
            onFrame?(nil)
            return
        }
        onFrame?(frames[frameIndex % frames.count])
    }
}

#endif
