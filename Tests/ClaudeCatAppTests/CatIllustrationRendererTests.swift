#if os(macOS)

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import ClaudeCatPet
@testable import ClaudeCatApp

final class CatIllustrationRendererTests: XCTestCase {
    private let accent = PetColor(r: 52, g: 120, b: 246, a: 255)
    private let pointSize = CGSize(width: 128, height: 128)
    private let backingScale = 2
    private let renderedColorTolerance = 24

    func testRendererProducesAntialiasedArtworkInsideTransparentSafeBounds() throws {
        let samples = [
            (label: "stage1", sample: sample(stage: 1)),
            (label: "stage4", sample: sample(stage: 4))
        ]

        for item in samples {
            try assertCommonRenderingInvariants(
                try render(sample: item.sample),
                label: item.label
            )
        }
    }

    func testAccentAppearsOnlyInTheGlowingScreen() throws {
        let active = try render(sample: sample(stage: 1))
        let accentPixel = Pixel(red: accent.r, green: accent.g, blue: accent.b, alpha: accent.a)

        let accentCoords = active.coordinates(matching: accentPixel, tolerance: renderedColorTolerance)
        let bounds = try XCTUnwrap(PixelBounds(coordinates: accentCoords))
        XCTAssertGreaterThan(accentCoords.count, 150)
        // In the side working view the lit laptop screen sits on the LEFT of the
        // 256px render (the cat looks left at it). X is not affected by the
        // bitmap flip, so it carries the real claim here. The row index is stored
        // top-first while Quartz draws bottom-up, so the vertical assertion only
        // says the screen is clear of both edges — a band that would survive the
        // flip in either direction.
        XCTAssertTrue(accentCoords.allSatisfy { $0.x >= 40 && $0.x <= 108 })
        XCTAssertGreaterThan(bounds.minY, 50)
        XCTAssertLessThan(bounds.maxY, 205)
    }

    func testWorkingUsesSideViewAndHoverUsesFrontView() throws {
        let working = try render(sample: sample(stage: 2))
        let hovering = try render(sample: sample(stage: 2, overlay: .hovering))
        let accentPixel = Pixel(red: accent.r, green: accent.g, blue: accent.b, alpha: accent.a)

        let workingAccent = working.coordinates(matching: accentPixel, tolerance: renderedColorTolerance)
        let hoveringAccent = hovering.coordinates(matching: accentPixel, tolerance: renderedColorTolerance)
        XCTAssertGreaterThan(workingAccent.count, 150)
        // Hover's whole accent budget is three thin "???" strokes rather than a
        // filled screen, so the floor here is much closer to what is drawn.
        XCTAssertGreaterThan(hoveringAccent.count, 120)

        // Working puts the accent in the lit screen on the left; hovering has no
        // screen at all and the accent survives only in the "???" climbing off
        // the head's top-right corner. X is not affected by the vertical bitmap
        // flip, so the centroids are comparable.
        let workingCenterX = averageX(workingAccent)
        let hoveringCenterX = averageX(hoveringAccent)
        XCTAssertLessThan(workingCenterX, 100)
        XCTAssertGreaterThan(hoveringCenterX, 110)
        XCTAssertGreaterThan(hoveringCenterX - workingCenterX, 30)
    }

    func testHoverAndClickDropTheLaptopWhileBrokenKeepsIt() throws {
        let working = try render(sample: sample(stage: 2))
        let hovering = try render(sample: sample(stage: 2, overlay: .hovering))
        let startled = try render(sample: sample(stage: 2, overlay: .startled))
        let accentPixel = Pixel(red: accent.r, green: accent.g, blue: accent.b, alpha: accent.a)

        // The lit screen is the only place the live accent can land in these
        // poses, so counting it is how we prove the laptop is gone. A startled
        // cat has dropped the laptop and has no "???" either, leaving no accent
        // at all; hovering keeps a small budget for the marks alone.
        XCTAssertEqual(startled.count(matching: accentPixel, tolerance: renderedColorTolerance), 0)

        let workingAccent = working.count(matching: accentPixel, tolerance: renderedColorTolerance)
        let hoveringAccent = hovering.count(matching: accentPixel, tolerance: renderedColorTolerance)
        XCTAssertGreaterThan(hoveringAccent, 120)
        XCTAssertLessThan(hoveringAccent, workingAccent / 2)

        // Broken still shows its laptop, so it must differ from the bare
        // startled cat by more than the eyes and the paw offsets.
        let broken = try render(sample: sample(stage: 2, behavior: .broken))
        XCTAssertGreaterThan(broken.differingPixelCount(from: startled), 1_000)
    }

    private func averageX(_ coordinates: [PixelCoordinate]) -> Double {
        guard !coordinates.isEmpty else { return 0 }
        return coordinates.reduce(0) { $0 + Double($1.x) } / Double(coordinates.count)
    }

    func testFirstAndLastStagesFitAndGrowInOrder() throws {
        let first = try render(sample: sample(stage: 0))
        let last = try render(sample: sample(stage: 5))
        let fur = Pixel(red: 0xB9, green: 0xAF, blue: 0xC0, alpha: 255)

        XCTAssertNotNil(first.alphaBounds)
        XCTAssertNotNil(last.alphaBounds)
        let firstFurPixels = first.count(matching: fur, tolerance: renderedColorTolerance)
        let lastFurPixels = last.count(matching: fur, tolerance: renderedColorTolerance)
        XCTAssertGreaterThan(firstFurPixels, 1_000)
        XCTAssertGreaterThan(lastFurPixels, firstFurPixels)

        for bitmap in [first, last] {
            let bounds = try XCTUnwrap(bitmap.alphaBounds)
            XCTAssertGreaterThanOrEqual(bounds.minX, 8)
            XCTAssertGreaterThanOrEqual(bounds.minY, 8)
            XCTAssertLessThan(bounds.maxX, bitmap.width - 8)
            XCTAssertLessThan(bounds.maxY, bitmap.height - 8)
        }
    }

    func testBrokenPoseIsVisibleDesaturatedAndDropsTheLiveAccent() throws {
        let live = try render(sample: sample(stage: 2))
        let broken = try render(sample: sample(stage: 2, behavior: .broken))
        let liveAccent = Pixel(red: accent.r, green: accent.g, blue: accent.b, alpha: accent.a)

        XCTAssertGreaterThan(broken.nontransparentPixelCount, 1_000)
        XCTAssertEqual(broken.count(matching: liveAccent, tolerance: renderedColorTolerance), 0)
        XCTAssertLessThan(broken.averageOpaqueChroma, live.averageOpaqueChroma * 0.35)
        XCTAssertGreaterThan(broken.differingPixelCount(from: live), 3_000)
    }

    func testSleepingPoseDimsTheScreenAndDiffersFromActive() throws {
        for stage in [1, 4] {
            let active = try render(sample: sample(stage: stage))
            let sleeping = try render(sample: sample(stage: stage, behavior: .sleeping))
            let accentPixel = Pixel(red: accent.r, green: accent.g, blue: accent.b, alpha: accent.a)

            XCTAssertNotNil(sleeping.alphaBounds, "stage \(stage)")
            XCTAssertGreaterThan(
                active.count(matching: accentPixel, tolerance: renderedColorTolerance),
                sleeping.count(matching: accentPixel, tolerance: renderedColorTolerance),
                "stage \(stage)"
            )
            XCTAssertGreaterThan(sleeping.differingPixelCount(from: active), 2_000, "stage \(stage)")
        }
    }

    func testZeroAndInvalidDestinationsLeaveTheBitmapUntouched() throws {
        let bitmap = try makeBitmap(width: 64, height: 64) { context in
            let currentSample = sample(stage: 0)
            CatIllustrationRenderer.draw(
                sample: currentSample,
                in: CGRect(x: 0, y: 0, width: 0, height: 64),
                context: context
            )
            CatIllustrationRenderer.draw(
                sample: currentSample,
                in: CGRect(x: CGFloat.nan, y: 0, width: 64, height: 64),
                context: context
            )
            CatIllustrationRenderer.draw(
                sample: currentSample,
                in: CGRect(x: 0, y: 0, width: -1, height: 64),
                context: context
            )
        }

        XCTAssertEqual(bitmap.nontransparentPixelCount, 0)
    }

    func testWritesSixStageContactSheetToTemporaryDirectory() throws {
        let cellWidth = Int(pointSize.width)
        let cellHeight = Int(pointSize.height)
        let bitmap = try makeBitmap(width: cellWidth * 6, height: cellHeight) { context in
            for stage in 0...5 {
                CatIllustrationRenderer.draw(
                    sample: sample(stage: stage, elapsed: 0.42),
                    in: CGRect(
                        x: CGFloat(stage * cellWidth),
                        y: 0,
                        width: pointSize.width,
                        height: pointSize.height
                    ),
                    context: context
                )
            }
        }
        let outputURL = URL(fileURLWithPath: "/tmp/claude-cat-six-stage-contact-sheet.png")

        try bitmap.writePNG(to: outputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertGreaterThan(try Data(contentsOf: outputURL).count, 1_000)
    }

    private func sample(
        stage: Int,
        behavior: PetBehaviorState = .jumping(frameInterval: 1.2),
        overlay: PetOverlay = .none,
        elapsed: TimeInterval = 0
    ) -> CatAnimationSample {
        CatAnimationPlanner.sample(
            stage: stage,
            behavior: behavior,
            overlay: overlay,
            elapsed: elapsed,
            accent: accent,
            reduceMotion: false
        )
    }

    private func render(sample: CatAnimationSample) throws -> RenderedBitmap {
        try makeBitmap(
            width: Int(pointSize.width) * backingScale,
            height: Int(pointSize.height) * backingScale
        ) { context in
            context.scaleBy(x: CGFloat(backingScale), y: CGFloat(backingScale))
            CatIllustrationRenderer.draw(
                sample: sample,
                in: CGRect(origin: .zero, size: pointSize),
                context: context
            )
        }
    }

    private func assertCommonRenderingInvariants(
        _ bitmap: RenderedBitmap,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let alphaBounds = try XCTUnwrap(bitmap.alphaBounds, file: file, line: line)
        let corners = [
            bitmap.pixel(x: 0, y: 0),
            bitmap.pixel(x: bitmap.width - 1, y: 0),
            bitmap.pixel(x: 0, y: bitmap.height - 1),
            bitmap.pixel(x: bitmap.width - 1, y: bitmap.height - 1)
        ]

        XCTAssertGreaterThan(bitmap.nontransparentPixelCount, 1_000, label, file: file, line: line)
        XCTAssertLessThan(
            bitmap.nontransparentPixelCount,
            bitmap.width * bitmap.height,
            label,
            file: file,
            line: line
        )
        XCTAssertTrue(
            bitmap.pixels.contains { $0.alpha > 0 && $0.alpha < 255 },
            label,
            file: file,
            line: line
        )
        XCTAssertTrue(corners.allSatisfy { $0.alpha == 0 }, label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(alphaBounds.minX, 10, label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(alphaBounds.minY, 10, label, file: file, line: line)
        XCTAssertLessThan(alphaBounds.maxX, bitmap.width - 10, label, file: file, line: line)
        XCTAssertLessThan(alphaBounds.maxY, bitmap.height - 10, label, file: file, line: line)
    }

    private func makeBitmap(
        width: Int,
        height: Int,
        drawing: (CGContext) -> Void
    ) throws -> RenderedBitmap {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        )
        drawing(context)
        let data = try XCTUnwrap(context.data)
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        return RenderedBitmap(
            width: width,
            height: height,
            bytes: Array(UnsafeBufferPointer(start: buffer, count: width * height * 4))
        )
    }
}

private struct Pixel: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    var chroma: Double {
        let channels = [red, green, blue]
        return Double((channels.max() ?? 0) - (channels.min() ?? 0))
    }

    func isClose(to other: Pixel, tolerance: Int) -> Bool {
        abs(Int(red) - Int(other.red)) <= tolerance
            && abs(Int(green) - Int(other.green)) <= tolerance
            && abs(Int(blue) - Int(other.blue)) <= tolerance
            && abs(Int(alpha) - Int(other.alpha)) <= tolerance
    }
}

private struct PixelCoordinate {
    let x: Int
    let y: Int
}

private struct PixelBounds {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int

    var width: Int {
        maxX - minX + 1
    }

    var height: Int {
        maxY - minY + 1
    }

    init?(coordinates: [PixelCoordinate]) {
        guard let first = coordinates.first else { return nil }
        self = coordinates.dropFirst().reduce(
            into: PixelBounds(
                minX: first.x,
                minY: first.y,
                maxX: first.x,
                maxY: first.y
            )
        ) { bounds, coordinate in
            bounds = PixelBounds(
                minX: min(bounds.minX, coordinate.x),
                minY: min(bounds.minY, coordinate.y),
                maxX: max(bounds.maxX, coordinate.x),
                maxY: max(bounds.maxY, coordinate.y)
            )
        }
    }

    init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }
}

private struct RenderedBitmap {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    var pixels: [Pixel] {
        stride(from: 0, to: bytes.count, by: 4).map {
            Pixel(
                red: bytes[$0],
                green: bytes[$0 + 1],
                blue: bytes[$0 + 2],
                alpha: bytes[$0 + 3]
            )
        }
    }

    var nontransparentPixelCount: Int {
        pixels.reduce(into: 0) { count, pixel in
            if pixel.alpha > 0 {
                count += 1
            }
        }
    }

    var alphaBounds: PixelBounds? {
        let coordinates = pixels.enumerated().compactMap { index, pixel -> PixelCoordinate? in
            guard pixel.alpha > 0 else { return nil }
            return PixelCoordinate(x: index % width, y: index / width)
        }
        guard let first = coordinates.first else { return nil }
        return coordinates.dropFirst().reduce(
            into: PixelBounds(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        ) { bounds, coordinate in
            bounds = PixelBounds(
                minX: min(bounds.minX, coordinate.x),
                minY: min(bounds.minY, coordinate.y),
                maxX: max(bounds.maxX, coordinate.x),
                maxY: max(bounds.maxY, coordinate.y)
            )
        }
    }

    var averageOpaqueChroma: Double {
        let opaquePixels = pixels.filter { $0.alpha == 255 }
        guard !opaquePixels.isEmpty else { return 0 }
        return opaquePixels.reduce(0) { $0 + $1.chroma } / Double(opaquePixels.count)
    }

    func pixel(x: Int, y: Int) -> Pixel {
        let index = (y * width + x) * 4
        return Pixel(
            red: bytes[index],
            green: bytes[index + 1],
            blue: bytes[index + 2],
            alpha: bytes[index + 3]
        )
    }

    func coordinates(matching target: Pixel, tolerance: Int) -> [PixelCoordinate] {
        pixels.enumerated().compactMap { index, pixel in
            guard pixel.isClose(to: target, tolerance: tolerance) else { return nil }
            return PixelCoordinate(x: index % width, y: index / width)
        }
    }

    func count(matching target: Pixel, tolerance: Int) -> Int {
        coordinates(matching: target, tolerance: tolerance).count
    }

    func differingPixelCount(from other: RenderedBitmap) -> Int {
        guard width == other.width, height == other.height else {
            return max(bytes.count, other.bytes.count) / 4
        }
        return zip(pixels, other.pixels).reduce(into: 0) { count, pair in
            if pair.0 != pair.1 {
                count += 1
            }
        }
    }

    func writePNG(to url: URL) throws {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                        | CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        )
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}

#endif
