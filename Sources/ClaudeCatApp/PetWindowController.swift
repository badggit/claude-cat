#if os(macOS)

import AppKit
import ClaudeCatCore
import ClaudeCatPet

// Window level and collection behavior for the desktop-pet overlay panel.
// PLACEHOLDER values: they MUST be replaced by the combo verified through the
// Phase-0 spike run in docs/wiki/testing-desktop-pet-macos-checklist.md.
struct PetWindowConfig {
    static let level: NSWindow.Level = .statusBar
    static let collectionBehavior: NSWindow.CollectionBehavior =
        [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
}

// Desktop-pet display layer: owns the single borderless non-activating
// NSPanel and routes cat illustration or pixel-art animation, fully stopping
// animation when the pet is occluded, the screen sleeps, or it is hidden.
// Like StatusItemController it is a
// pure subscriber — no tracker, no poll timer — so the engine can create and
// destroy it freely.
final class PetWindowController: NSObject, UsageDisplayLayer, PetLayerLifecycle {
    static let positionXKey = "petPositionX"
    static let positionYKey = "petPositionY"

    // Both presentation modes share one fixed 128 pt square.
    private static let petSide: CGFloat = 128
    // Bottom-right inset for the default position and off-screen clamping.
    private static let positionMargin: CGFloat = 24

    private let panel: NSPanel
    private let presentationView = NSView()
    private let spriteView: PetSpriteView
    private let illustrationView: CatIllustrationView
    private let failureView = PetPresentationFailureView()
    // Transparent event layer over either visual: drag, click, hover, right-click.
    private let interactionView = PetInteractionView()
    private let spriteCache: PetSpriteCache
    // Cycles the displayed frame within the energy budget; the controller only
    // feeds it snapshots and start/stop signals (occlusion, sleep, hide).
    private let animator: PetAnimator
    private let presentationRouter: PetPresentationRouter
    // Mirrors ClaudeCatConfig.suspiciousSkipThreshold for the broken-state check.
    private let suspiciousSkipThreshold: Int
    // Shared engine menu, handed to the interaction view for the right-click
    // popup so the pet reuses the exact menu the status item shows.
    private let sharedMenu: NSMenu
    // Invoked when show() finds no attached screens: the engine flips the
    // menu-bar display back on so the app never loses its last UI surface.
    private let onScreensUnavailable: () -> Void

    // Main-thread-only display state, cached from the engine's last apply.
    private var creatureID: String
    private var family: ModelFamily?
    // Latest behavior state and stage from apply(); re-pushed through the router
    // when only the interaction overlay changes so the base animation persists.
    private var lastState: PetBehaviorState = .sleeping
    private var lastStage = 0
    // The persistent interaction overlay (.none/.hovering/.dragging). .startled
    // is a one-shot poke and is never stored here.
    private var restingOverlay: PetOverlay = .none
    private var startleDeadline: Date?
    private var startleTimer: Timer?

    // Energy-budget inputs: the active surface runs only while shown, visible, and
    // the screen is awake. Each is tracked independently and combined below.
    private var isShown = false
    private var isOccluded = false
    private var screensAsleep = false

    private var screenObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    private var screensSleepObserver: NSObjectProtocol?
    private var screensWakeObserver: NSObjectProtocol?

    init(initialCreature: RenderedCreature,
         suspiciousSkipThreshold: Int,
         menu: NSMenu,
         onScreensUnavailable: @escaping () -> Void) {
        let cache = PetSpriteCache()
        let animator = PetAnimator(cache: cache)
        let spriteView = PetSpriteView()
        let illustrationView = CatIllustrationView(
            frame: NSRect(x: 0, y: 0, width: Self.petSide, height: Self.petSide)
        )
        self.spriteCache = cache
        self.animator = animator
        self.spriteView = spriteView
        self.illustrationView = illustrationView
        self.presentationRouter = MainActor.assumeIsolated {
            PetPresentationRouter(
                illustratedSurface: IllustratedCatPresentationSurface(view: illustrationView),
                pixelSurface: PixelPetPresentationSurface(animator: animator, view: spriteView)
            )
        }
        self.panel = NSPanel(contentRect: NSRect(x: 0, y: 0,
                                                 width: Self.petSide,
                                                 height: Self.petSide),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered,
                             defer: false)
        self.suspiciousSkipThreshold = suspiciousSkipThreshold
        self.sharedMenu = menu
        self.onScreensUnavailable = onScreensUnavailable
        self.creatureID = initialCreature.id
        super.init()
        configurePanel()
        animator.onFrame = { [weak self] image in
            self?.spriteView.image = image
        }
        MainActor.assumeIsolated {
            presentationRouter.onFailureChange = { [weak self] failure in
                self?.failureView.isHidden = failure == nil
            }
        }
        // Prewarm only pixel visuals; the illustrated cat draws directly at
        // the panel's backing scale and has no frame cache.
        if PetVisualCatalog.visual(id: creatureID)?.kind == .pixelArt {
            spriteCache.preload(creatureID: creatureID, family: nil)
        }
        pushToPresentation(overlay: .none)
    }

    deinit {
        startleTimer?.invalidate()
        MainActor.assumeIsolated {
            presentationRouter.stop()
        }
        removeObservers()
    }

    // MARK: - PetLayerLifecycle

    // Restores the persisted origin (sanitized against the current screen
    // layout) and orders the panel front without ever making it key.
    func show() {
        guard !NSScreen.screens.isEmpty else {
            onScreensUnavailable()
            return
        }
        panel.setFrameOrigin(sanitizedOrigin(saved: savedOrigin()))
        installObservers()
        panel.orderFrontRegardless()
        isShown = true
        // A freshly shown panel over an awake screen; observers correct these
        // if it is actually occluded or the screen later sleeps.
        isOccluded = !panel.occlusionState.contains(.visible)
        screensAsleep = false
        updatePresentationRunning()
    }

    func hide() {
        isShown = false
        updatePresentationRunning()
        removeObservers()
        panel.orderOut(nil)
    }

    // MARK: - UsageDisplayLayer

    // The accent color is ignored: pet sprites carry their own palette and
    // take the model tint from the snapshot's family via PetPalette.
    func apply(snapshot: DailyUsageSnapshot, accent: NSColor?, creature: RenderedCreature) {
        if PetVisualCatalog.visual(id: creature.id)?.kind == .pixelArt,
           creature.id != creatureID || snapshot.lastModelFamily != family {
            spriteCache.preload(creatureID: creature.id, family: snapshot.lastModelFamily)
        }
        creatureID = creature.id
        family = snapshot.lastModelFamily
        // The desktop pet uses a deliberately calmer tempo than the menu-bar
        // layer: a large 64px sprite bobbing on the desktop is far more
        // distracting than a 16px icon, so even peak usage stays a gentle bob
        // rather than a frantic hop.
        let base = PetStateEngine.baseState(snapshot: snapshot,
                                            suspiciousSkipThreshold: suspiciousSkipThreshold,
                                            slowestInterval: 2.5,
                                            fastestInterval: 0.7)
        let stageCount = PetVisualCatalog.stageCount(for: creatureID) ?? 0
        let stage = PetStateEngine.clampedStage(snapshot.stage, stageCount: stageCount)
        lastState = base
        lastStage = stage
        if base == .broken {
            clearStartleReaction()
        }
        // Preserve any live interaction overlay (hover/drag) across the snapshot
        // and any active click reaction across usage refreshes.
        pushToPresentation(overlay: effectiveOverlay())
    }

    // MARK: - Panel

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = PetWindowConfig.level
        panel.collectionBehavior = PetWindowConfig.collectionBehavior
        presentationView.frame = NSRect(x: 0, y: 0,
                                        width: Self.petSide,
                                        height: Self.petSide)
        spriteView.frame = NSRect(x: 0, y: 0, width: Self.petSide, height: Self.petSide)
        illustrationView.frame = presentationView.bounds
        failureView.frame = presentationView.bounds
        spriteView.autoresizingMask = [.width, .height]
        illustrationView.autoresizingMask = [.width, .height]
        failureView.autoresizingMask = [.width, .height]
        spriteView.isHidden = true
        illustrationView.isHidden = true
        failureView.isHidden = true
        presentationView.addSubview(spriteView)
        presentationView.addSubview(illustrationView)
        presentationView.addSubview(failureView)
        panel.contentView = presentationView
        installInteractionView()
    }

    // Puts the invisible event layer above both visuals and wires its callbacks
    // back to the controller: overlay changes drive the router, drag-end
    // sanitizes and persists the origin, and the shared menu backs right-click.
    private func installInteractionView() {
        interactionView.frame = presentationView.bounds
        interactionView.autoresizingMask = [.width, .height]
        interactionView.sharedMenu = sharedMenu
        interactionView.onOverlayChange = { [weak self] overlay in
            self?.handleOverlayChange(overlay)
        }
        interactionView.onDragEnded = { [weak self] in
            self?.handleDragEnded()
        }
        presentationView.addSubview(interactionView)
    }

    // MARK: - Interaction

    // Pushes mouse state through the shared router. A click reaction is timed
    // here so both presentation surfaces retain it across usage refreshes.
    private func handleOverlayChange(_ overlay: PetOverlay) {
        switch overlay {
        case .startled:
            beginStartleReaction()
        case .dragging:
            restingOverlay = overlay
            clearStartleReaction()
        case .none, .hovering:
            restingOverlay = overlay
        }
        pushToPresentation(overlay: effectiveOverlay())
    }

    private func pushToPresentation(overlay: PetOverlay) {
        _ = MainActor.assumeIsolated {
            presentationRouter.update(
                creatureID: creatureID,
                family: family,
                state: lastState,
                overlay: overlay,
                stage: lastStage
            )
        }
    }

    private func beginStartleReaction() {
        guard lastState != .broken, presentationShouldRun else { return }
        startleTimer?.invalidate()
        let deadline = Date().addingTimeInterval(PetStateEngine.startleDuration)
        startleDeadline = deadline
        let timer = Timer.scheduledTimer(
            withTimeInterval: PetStateEngine.startleDuration,
            repeats: false
        ) { [weak self] _ in
            self?.finishStartleReaction(deadline: deadline)
        }
        timer.tolerance = PetStateEngine.startleDuration * 0.3
        startleTimer = timer
    }

    private func finishStartleReaction(deadline: Date) {
        guard startleDeadline == deadline else { return }
        startleDeadline = nil
        startleTimer = nil
        pushToPresentation(overlay: restingOverlay)
    }

    private func clearStartleReaction() {
        startleTimer?.invalidate()
        startleTimer = nil
        startleDeadline = nil
    }

    private func effectiveOverlay(now: Date = Date()) -> PetOverlay {
        guard restingOverlay != .dragging,
              let deadline = startleDeadline else {
            return restingOverlay
        }
        if now < deadline {
            return .startled
        }
        clearStartleReaction()
        return restingOverlay
    }

    // The interaction view already moved the panel during the drag; snap the
    // final origin to a sanitized on-screen spot and persist it (design: the
    // position is saved after every drag).
    private func handleDragEnded() {
        let sanitized = sanitizedOrigin(saved: panel.frame.origin)
        panel.setFrameOrigin(sanitized)
        persistOrigin(sanitized)
    }

    private func persistOrigin(_ origin: CGPoint) {
        let defaults = UserDefaults.standard
        defaults.set(Double(origin.x), forKey: Self.positionXKey)
        defaults.set(Double(origin.y), forKey: Self.positionYKey)
    }

    // MARK: - Position

    // A saved origin exists only when both coordinates were persisted.
    private func savedOrigin() -> CGPoint? {
        let defaults = UserDefaults.standard
        guard let x = defaults.object(forKey: Self.positionXKey) as? Double,
              let y = defaults.object(forKey: Self.positionYKey) as? Double else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    private func sanitizedOrigin(saved: CGPoint?) -> CGPoint {
        let screens = NSScreen.screens
        let mainFrame = NSScreen.main?.visibleFrame
            ?? screens.first?.visibleFrame
            ?? .zero
        return PetGeometry.sanitizedOrigin(saved: saved,
                                           petSize: CGSize(width: Self.petSide,
                                                           height: Self.petSide),
                                           screenVisibleFrames: screens.map(\.visibleFrame),
                                           mainVisibleFrame: mainFrame,
                                           margin: Self.positionMargin)
    }

    // MARK: - Energy budget

    // The active surface runs only while the pet is shown, unoccluded, and the
    // screen is awake; otherwise its animation source is fully stopped.
    private var presentationShouldRun: Bool {
        isShown && !isOccluded && !screensAsleep
    }

    private func updatePresentationRunning() {
        let shouldRun = presentationShouldRun
        MainActor.assumeIsolated {
            presentationRouter.setRunning(shouldRun)
        }
        if !shouldRun, startleDeadline != nil || startleTimer != nil {
            clearStartleReaction()
            // The router is already stopped, so this restores the resting
            // input without restarting either animation source.
            pushToPresentation(overlay: restingOverlay)
        }
    }

    private func handleOcclusionChange() {
        isOccluded = !panel.occlusionState.contains(.visible)
        updatePresentationRunning()
    }

    private func handleScreensDidSleep() {
        screensAsleep = true
        updatePresentationRunning()
    }

    private func handleScreensDidWake() {
        screensAsleep = false
        updatePresentationRunning()
    }

    // MARK: - Observers

    private func installObservers() {
        let center = NotificationCenter.default
        if screenObserver == nil {
            screenObserver = center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main) { [weak self] _ in
                self?.handleScreenReconfiguration()
            }
        }
        // Window-level occlusion: stop animating when another window fully
        // covers the pet's Space (occlusionState drops .visible).
        if occlusionObserver == nil {
            occlusionObserver = center.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: panel,
                queue: .main) { [weak self] _ in
                self?.handleOcclusionChange()
            }
        }
        // Screen sleep/wake post on the workspace center, not the default one.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        if screensSleepObserver == nil {
            screensSleepObserver = workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main) { [weak self] _ in
                self?.handleScreensDidSleep()
            }
        }
        if screensWakeObserver == nil {
            screensWakeObserver = workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main) { [weak self] _ in
                self?.handleScreensDidWake()
            }
        }
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        if let observer = screenObserver {
            center.removeObserver(observer)
            screenObserver = nil
        }
        if let observer = occlusionObserver {
            center.removeObserver(observer)
            occlusionObserver = nil
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        if let observer = screensSleepObserver {
            workspaceCenter.removeObserver(observer)
            screensSleepObserver = nil
        }
        if let observer = screensWakeObserver {
            workspaceCenter.removeObserver(observer)
            screensWakeObserver = nil
        }
    }

    // Re-sanitizes the CURRENT panel origin (not the persisted one, which may
    // be stale after a drag) so unplugging a monitor relocates the pet onto
    // the main screen. A momentarily empty screen list (e.g. mid-reconfigure)
    // is left alone: the next notification with screens present repositions.
    private func handleScreenReconfiguration() {
        guard !NSScreen.screens.isEmpty else { return }
        panel.setFrameOrigin(sanitizedOrigin(saved: panel.frame.origin))
    }
}

// Presents one sprite frame. An NSImageView would smooth the 64px backing
// CGImage when rasterizing it at 128 pt (shouldInterpolate alone does not
// cover the AppKit draw scale), so the frame is drawn manually with context
// interpolation off to keep the pixels hard.
private final class PetSpriteView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        NSGraphicsContext.current?.cgContext.interpolationQuality = .none
        image.draw(in: bounds)
    }
}

// A routing failure must replace stale creature art with a visible, neutral
// status mark while leaving the transparent interaction layer operational.
private final class PetPresentationFailureView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.18
        context.setShouldAntialias(true)
        context.setFillColor(NSColor(calibratedWhite: 0.72, alpha: 0.72).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius,
                                       y: center.y - radius,
                                       width: radius * 2,
                                       height: radius * 2))
        context.setStrokeColor(NSColor(calibratedWhite: 0.30, alpha: 0.9).cgColor)
        context.setLineWidth(4)
        context.setLineCap(.round)
        let inset = radius * 0.48
        context.move(to: CGPoint(x: center.x - inset, y: center.y - inset))
        context.addLine(to: CGPoint(x: center.x + inset, y: center.y + inset))
        context.move(to: CGPoint(x: center.x - inset, y: center.y + inset))
        context.addLine(to: CGPoint(x: center.x + inset, y: center.y - inset))
        context.strokePath()
    }
}

#endif
