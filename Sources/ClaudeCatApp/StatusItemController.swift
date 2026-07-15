#if os(macOS)

import AppKit
import ClaudeCatCore

// Menu-bar display layer: owns the NSStatusItem and renders the usage
// snapshots the UsageEngine pushes into it. It holds no tracker and no poll
// timer — it is a pure subscriber that can be created and destroyed without
// affecting polling.
final class StatusItemController: UsageDisplayLayer {
    private let statusItem: NSStatusItem
    // Mirrors ClaudeCatConfig.suspiciousSkipThreshold for the broken-state check.
    private let suspiciousSkipThreshold: Int

    // Main-thread-only display state, cached from the engine's last apply.
    private var lastSnapshot: DailyUsageSnapshot?
    private var animationTimer: Timer?
    private var currentFrameInterval: TimeInterval = 0
    private var frameIndex = 0
    // Active model color; nil keeps the creature as an adaptive template image.
    private var accentColor: NSColor?
    private var creature: RenderedCreature

    init(menu: NSMenu, initialCreature: RenderedCreature, suspiciousSkipThreshold: Int) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.creature = initialCreature
        self.suspiciousSkipThreshold = suspiciousSkipThreshold
        statusItem.button?.imagePosition = .imageLeft
        setButtonImage(initialCreature.idleImage)
        statusItem.menu = menu
    }

    deinit {
        animationTimer?.invalidate()
    }

    // UsageDisplayLayer: called by the engine on the main thread with the
    // accent color and active creature already resolved.
    func apply(snapshot: DailyUsageSnapshot, accent: NSColor?, creature: RenderedCreature) {
        lastSnapshot = snapshot
        accentColor = accent
        self.creature = creature

        let looksBroken = !snapshot.transcriptsFolderFound
            || snapshot.suspiciousSkipCount > suspiciousSkipThreshold
        if looksBroken {
            stopAnimation()
            setButtonImage(creature.brokenImage)
            return
        }

        if snapshot.isIdle {
            stopAnimation()
            setButtonImage(creature.idleImage)
            return
        }

        let interval = StageEngine.frameInterval(tokensPerMinute: snapshot.tokensPerMinute,
                                                 slowest: 1.0,
                                                 fastest: 0.15)
        startAnimation(interval: interval)
        renderCurrentFrame()
    }

    // Recreates the animation timer only when the interval actually changed,
    // so steady usage does not restart the cycle every poll.
    private func startAnimation(interval: TimeInterval) {
        if animationTimer != nil, abs(interval - currentFrameInterval) < 0.001 {
            return
        }
        animationTimer?.invalidate()
        currentFrameInterval = interval
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval,
                                              repeats: true) { [weak self] _ in
            self?.advanceFrame()
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        currentFrameInterval = 0
        frameIndex = 0
    }

    private func advanceFrame() {
        frameIndex &+= 1
        renderCurrentFrame()
    }

    private func renderCurrentFrame() {
        guard let snapshot = lastSnapshot else { return }
        let frames = creature.imageFrames(stage: snapshot.stage)
        setButtonImage(frames[frameIndex % frames.count])
    }

    // Tints the whole cat with the active model color; with no color the
    // template image is used as-is so it adapts to light/dark menu bars.
    private func setButtonImage(_ image: NSImage) {
        guard let color = accentColor else {
            statusItem.button?.image = image
            return
        }
        statusItem.button?.image = Self.tinted(image, with: color)
    }

    // Recolors a monochrome template silhouette by filling its opaque pixels
    // with the given color (sourceAtop keeps the alpha, replaces the color).
    private static func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }
}

#endif
