// Pure screen-coordinate math for placing the pet window.
// Uses AppKit-style coordinates (y grows upward); callers pass
// `visibleFrame` rects, which already exclude the Dock and menu bar.
// Window creation and origin persistence live in the app layer, not here.

import Foundation
// On Apple platforms the CGRect helper accessors (minX, maxX, width...)
// live in CoreGraphics; Linux Foundation ships them built in.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum PetGeometry {
    // Minimum overlap (per axis) between the pet rect and a screen's
    // visible frame for a saved position to still count as on-screen.
    public static let minVisibleEdge: CGFloat = 32

    // Bottom-right corner of the main screen's visible frame, inset by
    // `margin`; the bottom edge is `minY` because y grows upward.
    public static func defaultOrigin(mainVisibleFrame: CGRect,
                                     petSize: CGSize,
                                     margin: CGFloat) -> CGPoint {
        CGPoint(x: mainVisibleFrame.maxX - margin - petSize.width,
                y: mainVisibleFrame.minY + margin)
    }

    // Restores a persisted origin: kept as-is while the pet stays
    // sufficiently visible on any screen (multi-monitor layouts survive),
    // otherwise moved to the nearest spot fully inside the main screen.
    public static func sanitizedOrigin(saved: CGPoint?,
                                       petSize: CGSize,
                                       screenVisibleFrames: [CGRect],
                                       mainVisibleFrame: CGRect,
                                       margin: CGFloat) -> CGPoint {
        guard let saved else {
            return defaultOrigin(mainVisibleFrame: mainVisibleFrame,
                                 petSize: petSize,
                                 margin: margin)
        }
        let petRect = CGRect(origin: saved, size: petSize)
        if screenVisibleFrames.contains(where: { isSufficientlyVisible(petRect, on: $0) }) {
            return saved
        }
        return CGPoint(x: clamped(saved.x,
                                  lower: mainVisibleFrame.minX,
                                  upper: mainVisibleFrame.maxX - petSize.width),
                       y: clamped(saved.y,
                                  lower: mainVisibleFrame.minY,
                                  upper: mainVisibleFrame.maxY - petSize.height))
    }

    // Visible means the overlap region reaches minVisibleEdge in both
    // dimensions; anything thinner is unreachable enough to relocate.
    // A pet smaller than minVisibleEdge only needs to be fully overlapped.
    private static func isSufficientlyVisible(_ petRect: CGRect, on frame: CGRect) -> Bool {
        let overlapWidth = min(petRect.maxX, frame.maxX) - max(petRect.minX, frame.minX)
        let overlapHeight = min(petRect.maxY, frame.maxY) - max(petRect.minY, frame.minY)
        return overlapWidth >= min(minVisibleEdge, petRect.width)
            && overlapHeight >= min(minVisibleEdge, petRect.height)
    }

    // Lower bound wins when the pet is larger than the main frame.
    private static func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        max(lower, min(value, upper))
    }
}
