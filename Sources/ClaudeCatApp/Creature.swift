#if os(macOS)

import AppKit

// Raw art for one creature: growth stages plus idle and broken states, all as
// ASCII pixel maps ('#' = opaque, anything else = transparent).
struct CreatureArt {
    let id: String
    let displayName: String
    let stageNames: [String]
    let stageMaps: [[[String]]]
    let idleMap: [String]
    let brokenMap: [String]
}

// A creature with its ASCII maps rasterized once into template NSImages.
final class RenderedCreature {
    let id: String
    let displayName: String
    let stageNames: [String]
    let stageImages: [[NSImage]]
    let idleImage: NSImage
    let brokenImage: NSImage

    init(art: CreatureArt) {
        self.id = art.id
        self.displayName = art.displayName
        self.stageNames = art.stageNames
        self.stageImages = art.stageMaps.map { $0.map(CreatureRenderer.render) }
        self.idleImage = CreatureRenderer.render(art.idleMap)
        self.brokenImage = CreatureRenderer.render(art.brokenMap)
    }

    // Stage is clamped so an out-of-bounds value never crashes.
    func imageFrames(stage: Int) -> [NSImage] {
        let clamped = min(max(stage, 0), stageImages.count - 1)
        return stageImages[clamped]
    }
}

enum CreatureRenderer {
    // Menu bar is 22 pt tall; 18 pt keeps a little breathing room.
    static let pointSize: CGFloat = 18
    private static let grid = 16

    // Pads or trims each map to a fixed 16x16 grid so hand-drawn rows of
    // slightly wrong length still render aligned and never crash.
    private static func normalized(_ rows: [String]) -> [String] {
        var result = rows.map { row -> String in
            let trimmed = String(row.prefix(grid))
            return trimmed + String(repeating: ".", count: max(0, grid - trimmed.count))
        }
        while result.count < grid { result.append(String(repeating: ".", count: grid)) }
        return Array(result.prefix(grid))
    }

    // Renders an ASCII pixel map into a monochrome template image; AppKit
    // invokes the drawing handler per backing scale factor, so Retina screens
    // get a crisp 2x rasterization for free.
    static func render(_ rawRows: [String]) -> NSImage {
        let rows = normalized(rawRows)
        let size = NSSize(width: pointSize, height: pointSize)
        // flipped: true puts the origin at the top-left, matching map order.
        let image = NSImage(size: size, flipped: true) { _ in
            let cell = pointSize / CGFloat(grid)
            NSColor.black.setFill()
            for (y, row) in rows.enumerated() {
                for (x, char) in row.enumerated() where char == "#" {
                    NSRect(x: CGFloat(x) * cell,
                           y: CGFloat(y) * cell,
                           width: cell,
                           height: cell).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

// Registry of all creatures the user can pick from in the menu.
enum CreatureCatalog {
    static let defaultID = "cat"

    static let all: [RenderedCreature] = [
        CreatureArt.cat,
        CreatureArt.bunny,
        CreatureArt.bird,
        CreatureArt.flower,
        CreatureArt.pig
    ].map(RenderedCreature.init)

    // Falls back to the first creature if the stored id is unknown.
    static func creature(id: String) -> RenderedCreature {
        all.first { $0.id == id } ?? all[0]
    }
}

#endif
