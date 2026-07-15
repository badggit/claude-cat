#if os(macOS)

import AppKit
import ClaudeCatCore
import ClaudeCatPet

// Wraps a frame's raw RGBA bytes in a CGImage-backed NSImage. Rendering is
// pure byte-wrapping (no focus locking, no per-frame tinting) so it stays
// cheap enough to run once per sprite and cache forever.
enum PetSpriteRenderer {
    // Point size the 64px sprite is presented at (2x integer scale); the
    // backing CGImage stays 64x64 and scales without interpolation.
    static let pointSize: CGFloat = 128

    static func image(frame: PetFrame, palette: PetPalette, accent: PetColor) -> NSImage {
        let bytes = PetFrameBitmap.rgba(frame: frame, palette: palette, accent: accent)
        let size = NSSize(width: pointSize, height: pointSize)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(width: petGrid,
                                    height: petGrid,
                                    bitsPerComponent: 8,
                                    bitsPerPixel: 32,
                                    bytesPerRow: petGrid * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                    provider: provider,
                                    decode: nil,
                                    shouldInterpolate: false,
                                    intent: .defaultIntent) else {
            // Unreachable with a well-formed byte buffer; an empty image
            // keeps the pet invisible instead of crashing the menu-bar app.
            return NSImage(size: size)
        }
        return NSImage(cgImage: cgImage, size: size)
    }
}

enum PetSpriteState: CaseIterable {
    case jump
    case sleep
    case drag
    case hover
    case broken
}

// Memoizing sprite store: each creature+stage+state+accent-family combination
// is rendered exactly once, so animation ticks only swap prebuilt NSImages.
final class PetSpriteCache {
    private struct Key: Hashable {
        let creatureID: String
        let stage: Int
        let state: PetSpriteState
        let family: ModelFamily?
    }

    private let palette = PetPalette.standard
    private var cache: [Key: [NSImage]] = [:]

    // Returns the prebuilt frame images for the combination, rendering and
    // memoizing on first request. Unknown creature IDs yield an empty array.
    func frames(creatureID: String, stage: Int, state: PetSpriteState, family: ModelFamily?) -> [NSImage] {
        // Broken art is creature-level, so all stages share one cache entry.
        let key = Key(creatureID: creatureID,
                      stage: state == .broken ? 0 : stage,
                      state: state,
                      family: family)
        if let cached = cache[key] {
            return cached
        }
        guard let art = PetArtCatalog.creature(id: creatureID) else {
            // Memoize the miss too; otherwise every animation tick re-scans
            // the catalog for an ID that will never appear.
            cache[key] = []
            return []
        }
        let accent = PetPalette.accentColor(for: family)
        let images = sourceFrames(art: art, stage: key.stage, state: state).map {
            PetSpriteRenderer.image(frame: $0, palette: palette, accent: accent)
        }
        cache[key] = images
        return images
    }

    // Renders every stage and state up front so attaching the pet or
    // switching creatures never pays render cost mid-animation.
    func preload(creatureID: String, family: ModelFamily?) {
        guard let art = PetArtCatalog.creature(id: creatureID) else { return }
        for stage in art.stages.indices {
            for state in PetSpriteState.allCases {
                _ = frames(creatureID: creatureID, stage: stage, state: state, family: family)
            }
        }
    }

    private func sourceFrames(art: PetCreatureArt, stage: Int, state: PetSpriteState) -> [PetFrame] {
        let sprites = art.stageSprites(stage: stage)
        switch state {
        case .jump:
            return sprites.jump
        case .sleep:
            return sprites.sleep
        case .drag:
            return [sprites.drag]
        case .hover:
            return [sprites.hover]
        case .broken:
            return art.broken
        }
    }
}

#endif
