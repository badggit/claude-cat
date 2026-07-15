#if os(macOS)

import AppKit

// Phase-0 spike: a single borderless non-activating NSPanel that stands in for
// the desktop pet. It exists only to validate the five overlay-window premises
// on a real Mac. No tracker, no menu bar item, no timers — the checklist in
// docs/wiki/testing-desktop-pet-macos-checklist.md drives the manual run.
final class PetSpikeController: NSObject {
    private struct SpikeCombo {
        let name: String
        let level: NSWindow.Level
        let behavior: NSWindow.CollectionBehavior
    }

    // The 12 window-configuration combos the tester cycles through: four
    // window levels crossed with three collection-behavior sets.
    private static let combos: [SpikeCombo] = {
        let levels: [(name: String, level: NSWindow.Level)] = [
            (name: ".floating", level: .floating),
            (name: ".statusBar", level: .statusBar),
            (name: ".popUpMenu", level: .popUpMenu),
            (name: ".screenSaver", level: .screenSaver)
        ]
        let behaviors: [(name: String, behavior: NSWindow.CollectionBehavior)] = [
            (name: "[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]",
             behavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]),
            (name: "[.canJoinAllSpaces, .fullScreenAuxiliary]",
             behavior: [.canJoinAllSpaces, .fullScreenAuxiliary]),
            (name: "[.moveToActiveSpace, .fullScreenAuxiliary]",
             behavior: [.moveToActiveSpace, .fullScreenAuxiliary])
        ]
        return levels.flatMap { level in
            behaviors.map { behavior in
                SpikeCombo(name: "\(level.name) + \(behavior.name)",
                           level: level.level,
                           behavior: behavior.behavior)
            }
        }
    }()

    private let panel: NSPanel
    private let squareView = SpikeSquareView()
    private let comboMenu = NSMenu()
    private var appliedComboIndex = 0

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 128, height: 128),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        super.init()
        configurePanel()
        buildComboMenu()
        applyCombo(at: 0)
    }

    func show() {
        panel.center()
        panel.orderFrontRegardless()
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        // The spike's drag is implemented manually in the content view so a
        // click and a drag can be told apart; window-background dragging
        // would swallow that distinction.
        panel.isMovableByWindowBackground = false
        squareView.frame = NSRect(x: 0, y: 0, width: 128, height: 128)
        squareView.onRightClick = { [weak self] event in
            self?.showComboMenu(for: event)
        }
        panel.contentView = squareView
    }

    private func buildComboMenu() {
        comboMenu.autoenablesItems = false
        for (index, combo) in Self.combos.enumerated() {
            let item = NSMenuItem(title: combo.name,
                                  action: #selector(selectCombo(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = index
            comboMenu.addItem(item)
        }
        comboMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit",
                              action: #selector(quit(_:)),
                              keyEquivalent: "q")
        quit.target = self
        comboMenu.addItem(quit)
    }

    // Premise 3 check: the popped-up menu must render ABOVE the panel even at
    // the highest window levels, and dismiss normally.
    private func showComboMenu(for event: NSEvent) {
        for item in comboMenu.items where item.action == #selector(selectCombo(_:)) {
            item.state = item.tag == appliedComboIndex ? .on : .off
        }
        let location = squareView.convert(event.locationInWindow, from: nil)
        _ = comboMenu.popUp(positioning: nil, at: location, in: squareView)
    }

    @objc private func selectCombo(_ sender: NSMenuItem) {
        applyCombo(at: sender.tag)
    }

    // Applies the combo live and prints its name so the tester can record on
    // stdout which configuration was active when a premise passed or failed.
    private func applyCombo(at index: Int) {
        guard Self.combos.indices.contains(index) else { return }
        let combo = Self.combos[index]
        appliedComboIndex = index
        panel.level = combo.level
        panel.collectionBehavior = combo.behavior
        print("Applied combo: \(combo.name)")
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}

// Draws a 96 pt gray square centered in the 128 pt frame and turns raw mouse
// events into the spike gestures: manual drag, hover lighten, click flash,
// right-click menu. The 16 pt margin around the square is intentionally left
// undrawn (alpha 0) — premise 4 tests dragging over transparent pixels.
private final class SpikeSquareView: NSView {
    var onRightClick: ((NSEvent) -> Void)?

    private static let squareSide: CGFloat = 96
    // Movement below this many points still counts as a click, not a drag.
    private static let dragThreshold: CGFloat = 3

    private var isHovered = false
    private var isFlashing = false
    private var dragStartMouseLocation = NSPoint.zero
    private var dragStartWindowOrigin = NSPoint.zero
    private var didDrag = false

    override func draw(_ dirtyRect: NSRect) {
        fillColor.setFill()
        squareRect.fill()
    }

    private var squareRect: NSRect {
        NSRect(x: (bounds.width - Self.squareSide) / 2,
               y: (bounds.height - Self.squareSide) / 2,
               width: Self.squareSide,
               height: Self.squareSide)
    }

    private var fillColor: NSColor {
        if isFlashing { return NSColor(white: 0.95, alpha: 1) }
        if isHovered { return NSColor(white: 0.75, alpha: 1) }
        return NSColor(white: 0.55, alpha: 1)
    }

    // The panel never becomes key (premise 1), so the very first click while
    // another app is active must already be delivered to this view.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self,
                                       userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin ?? .zero
        didDrag = false
    }

    // Manual drag in screen coordinates: the window follows the mouse by the
    // delta from the press point, so grabbing any pixel of the frame works.
    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        let dx = location.x - dragStartMouseLocation.x
        let dy = location.y - dragStartMouseLocation.y
        if !didDrag && abs(dx) < Self.dragThreshold && abs(dy) < Self.dragThreshold {
            return
        }
        didDrag = true
        window?.setFrameOrigin(NSPoint(x: dragStartWindowOrigin.x + dx,
                                       y: dragStartWindowOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDrag else { return }
        flash()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    // Brief brightness pulse confirming the press was recognized as a click
    // rather than a drag.
    private func flash() {
        isFlashing = true
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.isFlashing = false
            self?.needsDisplay = true
        }
    }
}

#endif
