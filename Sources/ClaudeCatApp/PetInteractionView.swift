#if os(macOS)

import AppKit
import ClaudeCatPet

// Transparent event surface layered over the pet sprite. It owns the pet's raw
// mouse-event stream (drag, click, hover, right-click) and reports the facts
// back to the window controller through callbacks; it holds no engine or
// animator internals beyond the injected shared menu. The pet panel is
// non-activating and never becomes key, so this view must handle the first
// click WITHOUT activating the app (the never-steal-focus design invariant).
final class PetInteractionView: NSView {
    // Movement (in screen points) below which a press is still a click, not a
    // drag. Matched against NSEvent.mouseLocation like the Phase-0 spike.
    private static let dragThreshold: CGFloat = 3

    // Shared engine menu, popped up on right-click; no second menu is built.
    var sharedMenu: NSMenu?
    // Reports the current interaction overlay (.hovering/.dragging/.none) or a
    // one-shot .startled on a click. The controller owns the shared reaction
    // deadline and forwards the resulting overlay to the active presentation.
    var onOverlayChange: ((PetOverlay) -> Void)?
    // Fires once a drag ends so the controller can sanitize and persist the
    // panel's new origin (the view has already moved the window during the drag).
    var onDragEnded: (() -> Void)?

    // Screen-coordinate press anchor (like the spike) so grabbing any pixel of
    // the frame — including the transparent margin — drags by the same delta.
    private var dragStartMouseLocation = NSPoint.zero
    private var dragStartWindowOrigin = NSPoint.zero
    // True only from the moment a press crosses the drag threshold until the
    // matching mouseUp; distinguishes a click from a drag and suppresses hover
    // toggles mid-drag.
    private var isDragging = false
    private var isHovering = false

    // The panel never becomes key, so the very first click while another app is
    // frontmost must already be delivered here — and returning true never
    // activates this app (the click acts in place).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // Claim every point inside the 128 pt bounds so hit-testing never falls
    // through the sprite's alpha-0 pixels to a window underneath (spike
    // premise 4). The view draws nothing, so the pet stays visually transparent.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    // MARK: - Tracking area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        // .inVisibleRect keeps the area sized to the view automatically (the
        // passed rect is ignored); .activeAlways because this app is never the
        // active app yet the pet must still light up on hover.
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited,
                                                 .activeAlways,
                                                 .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        guard !isDragging else { return }
        onOverlayChange?(.hovering)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        guard !isDragging else { return }
        onOverlayChange?(.none)
    }

    // MARK: - Mouse drag / click

    override func mouseDown(with event: NSEvent) {
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin ?? .zero
        isDragging = false
    }

    // Manual drag in screen coordinates: the window follows the mouse by the
    // delta from the press point, so grabbing any pixel of the frame works.
    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        let dx = location.x - dragStartMouseLocation.x
        let dy = location.y - dragStartMouseLocation.y
        if !isDragging && abs(dx) < Self.dragThreshold && abs(dy) < Self.dragThreshold {
            return
        }
        if !isDragging {
            isDragging = true
            onOverlayChange?(.dragging)
        }
        window?.setFrameOrigin(NSPoint(x: dragStartWindowOrigin.x + dx,
                                       y: dragStartWindowOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            onDragEnded?()
            // The pet followed the cursor, so resume the resting overlay based
            // on whether the mouse is still over it.
            isHovering = bounds.contains(convert(event.locationInWindow, from: nil))
            onOverlayChange?(isHovering ? .hovering : .none)
        } else {
            // A plain click starts the controller-owned reaction window.
            onOverlayChange?(.startled)
        }
    }

    // MARK: - Right-click menu

    // Pops up the SAME engine menu above the pet without activating the app.
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = sharedMenu else { return }
        // Force the delegate to rebuild items so `size` reflects the real menu
        // height before positioning; popUp will refresh it again harmlessly.
        menu.update()
        // popUp places the menu's top-left corner at this point and grows
        // downward, so offsetting up by the menu height lands its bottom edge at
        // the pet's top edge — the menu opens fully ABOVE the pet.
        let anchor = NSPoint(x: bounds.minX, y: bounds.maxY + menu.size.height)
        menu.popUp(positioning: nil, at: anchor, in: self)
    }
}

#endif
