#if os(macOS)

import CoreGraphics
import ClaudeCatPet

enum CatIllustrationRenderer {
    private enum Metrics {
        static let canvasSide: CGFloat = 128
        static let outlineWidth: CGFloat = 2.6
        static let detailWidth: CGFloat = 2.1
        static let bodyPivot = CGPoint(x: 64, y: 62)
        // The side laptop's lid, hinged along the keyboard deck's back edge and
        // leaning away from the viewer. The deck is drawn after the lid, so it
        // covers the hinge seam.
        static let sideLid = LidQuad(
            bottomLeft: CGPoint(x: 24, y: 32.5),
            bottomRight: CGPoint(x: 52, y: 29),
            topRight: CGPoint(x: 48, y: 54),
            topLeft: CGPoint(x: 20, y: 57.5)
        )
        static let sidePanelInset: CGFloat = 0.87
    }

    // A flat quad in canvas space. The laptop lid and its screen panel are the
    // same rectangle at two depths, so the panel is the lid shrunk about its
    // own center and the perspective stays consistent between them.
    private struct LidQuad {
        let bottomLeft: CGPoint
        let bottomRight: CGPoint
        let topRight: CGPoint
        let topLeft: CGPoint

        func inset(by factor: CGFloat) -> LidQuad {
            let centerX = (bottomLeft.x + bottomRight.x + topRight.x + topLeft.x) / 4
            let centerY = (bottomLeft.y + bottomRight.y + topRight.y + topLeft.y) / 4
            func shrink(_ point: CGPoint) -> CGPoint {
                CGPoint(
                    x: centerX + (point.x - centerX) * factor,
                    y: centerY + (point.y - centerY) * factor
                )
            }
            return LidQuad(
                bottomLeft: shrink(bottomLeft),
                bottomRight: shrink(bottomRight),
                topRight: shrink(topRight),
                topLeft: shrink(topLeft)
            )
        }
    }

    private enum Palette {
        static let fur = IllustrationColor(hex: 0xB9AFC0)
        static let furShadow = IllustrationColor(hex: 0x94899B)
        static let highlight = IllustrationColor(hex: 0xF4E7D5)
        static let markings = IllustrationColor(hex: 0x817184)
        static let outline = IllustrationColor(hex: 0x514A50)
        static let cheeks = IllustrationColor(hex: 0xDCA6AF)
        static let keyboardBase = IllustrationColor(hex: 0x6E6A75)
        static let keyboardShade = IllustrationColor(hex: 0x565159)
        static let keyboardHighlight = IllustrationColor(hex: 0x9995A1)
        static let screenBezel = IllustrationColor(hex: 0x484149)
        static let screenEdge = IllustrationColor(hex: 0x302C32)
        static let screenOff = IllustrationColor(hex: 0x6C6A70)
        static let screenHighlight = IllustrationColor(hex: 0xFFFFFF)
    }

    // Screen appearance for the laptop the cat works at.
    private enum LaptopScreen {
        case on
        case dim
        case off
    }

    // Camera angle for a pose. Working and sleeping are shown from the side at
    // the laptop; pointer/click/broken keep the front-on view; dragging drops the
    // laptop and shows the cat lifted by the scruff.
    private enum CatView {
        case front
        case side
        case grabbed
    }

    static func draw(
        sample: CatAnimationSample,
        in destination: CGRect,
        context: CGContext
    ) {
        guard destination.origin.x.isFinite,
              destination.origin.y.isFinite,
              destination.width.isFinite,
              destination.height.isFinite,
              destination.width > 0,
              destination.height > 0 else {
            return
        }

        let side = min(destination.width, destination.height)
        let origin = CGPoint(
            x: destination.midX - side / 2,
            y: destination.midY - side / 2
        )

        context.saveGState()
        defer { context.restoreGState() }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(
            x: side / Metrics.canvasSide,
            y: side / Metrics.canvasSide
        )

        switch view(for: sample.pose) {
        case .front:
            drawFrontScene(sample: sample, context: context)
        case .side:
            drawSideScene(sample: sample, context: context)
        case .grabbed:
            drawGrabbedScene(sample: sample, context: context)
        }
    }

    private static func view(for pose: CatPose) -> CatView {
        switch pose {
        case .active, .sleeping:
            return .side
        case .hovering, .startled, .broken:
            return .front
        case .dragging:
            return .grabbed
        }
    }

    private static func screenState(for sample: CatAnimationSample) -> LaptopScreen {
        switch sample.pose {
        case .broken:
            return .off
        case .sleeping:
            return .dim
        case .active, .hovering, .startled, .dragging:
            return .on
        }
    }

    // Applies the growth scale and breathing squash around the body pivot for
    // the duration of the passed drawing block.
    private static func withBodyTransform(
        sample: CatAnimationSample,
        context: CGContext,
        _ body: (CGContext) -> Void
    ) {
        context.saveGState()
        context.translateBy(x: Metrics.bodyPivot.x, y: Metrics.bodyPivot.y)
        context.scaleBy(
            x: CGFloat(sample.bodyScale),
            y: CGFloat(sample.bodyScale) * (1 + CGFloat(sample.bodyBreath))
        )
        context.translateBy(x: -Metrics.bodyPivot.x, y: -Metrics.bodyPivot.y)
        body(context)
        context.restoreGState()
    }

    // MARK: - Front scene (pointer / click / broken)

    // The front-on cat turns to face us. When it still has its laptop, the body
    // and head render first, the laptop is layered over the lower body, and the
    // paws land on the keys in front of everything. Hovering drops the laptop
    // and adds rising "???" instead.
    private static func drawFrontScene(sample: CatAnimationSample, context: CGContext) {
        withBodyTransform(sample: sample, context: context) { context in
            drawTail(sample: sample, context: context)
            drawBody(sample: sample, context: context)
            drawHead(sample: sample, context: context)
        }
        if showsLaptop(in: sample.pose) {
            drawLaptop(sample: sample, screen: screenState(for: sample), context: context)
        }
        withBodyTransform(sample: sample, context: context) { context in
            drawPaws(sample: sample, context: context)
        }
        if sample.pose == .hovering {
            drawThinkMarks(sample: sample, context: context)
        }
    }

    // Pointer interaction takes the cat away from its work, so hover drops the
    // laptop. The click reaction drops it too: a click almost always lands on an
    // already-hovered cat, and keeping the laptop there would flash it back for
    // the length of the startle. Broken keeps it — the dead "no signal" screen
    // is how the tracking failure reads.
    private static func showsLaptop(in pose: CatPose) -> Bool {
        switch pose {
        case .hovering, .startled, .dragging:
            return false
        case .active, .sleeping, .broken:
            return true
        }
    }

    private static func drawLaptop(
        sample: CatAnimationSample,
        screen: LaptopScreen,
        context: CGContext
    ) {
        let screenRect = CGRect(x: 45.5, y: 37, width: 37, height: 19)
        let bezel = CGPath(
            roundedRect: CGRect(x: 42, y: 34, width: 44, height: 25),
            cornerWidth: 4,
            cornerHeight: 4,
            transform: nil
        )
        fillAndStroke(
            bezel,
            fill: Palette.screenBezel,
            stroke: Palette.outline,
            sample: sample,
            lineWidth: 2.0,
            context: context
        )

        let panel = CGPath(
            roundedRect: screenRect,
            cornerWidth: 2.5,
            cornerHeight: 2.5,
            transform: nil
        )
        switch screen {
        case .on, .dim:
            // The model-family accent stays a pure, readable color when fully
            // lit; a white bloom rides the glow value on top.
            let base: CGFloat = screen == .on ? 1.0 : 0.3
            fill(panel, color: IllustrationColor(sample.accent), sample: sample, alpha: base, context: context)
            let bloom = CGPath(
                roundedRect: screenRect.insetBy(dx: 4, dy: 4),
                cornerWidth: 2,
                cornerHeight: 2,
                transform: nil
            )
            fill(
                bloom,
                color: Palette.screenHighlight,
                sample: sample,
                alpha: 0.28 * CGFloat(sample.screenGlow),
                context: context
            )
        case .off:
            fill(panel, color: Palette.screenOff, sample: sample, context: context)
            let mark = CGMutablePath()
            mark.move(to: CGPoint(x: screenRect.midX - 5, y: screenRect.midY - 5))
            mark.addLine(to: CGPoint(x: screenRect.midX + 5, y: screenRect.midY + 5))
            mark.move(to: CGPoint(x: screenRect.midX - 5, y: screenRect.midY + 5))
            mark.addLine(to: CGPoint(x: screenRect.midX + 5, y: screenRect.midY - 5))
            stroke(mark, color: Palette.outline, sample: sample, lineWidth: 1.8, context: context)
        }

        // Keyboard base: a shallow trapezoid receding away from the viewer.
        let keyboard = CGMutablePath()
        keyboard.move(to: CGPoint(x: 34, y: 18))
        keyboard.addLine(to: CGPoint(x: 94, y: 18))
        keyboard.addLine(to: CGPoint(x: 88, y: 33))
        keyboard.addLine(to: CGPoint(x: 40, y: 33))
        keyboard.closeSubpath()
        fillAndStroke(
            keyboard,
            fill: Palette.keyboardBase,
            stroke: Palette.outline,
            sample: sample,
            lineWidth: 2.2,
            context: context
        )

        let keys = CGMutablePath()
        for row in 0..<3 {
            let y = 22 + CGFloat(row) * 4
            let inset = CGFloat(row) * 1.2
            keys.move(to: CGPoint(x: 42 + inset, y: y))
            keys.addLine(to: CGPoint(x: 86 - inset, y: y))
        }
        stroke(keys, color: Palette.keyboardShade, sample: sample, lineWidth: 1.4, context: context)
    }

    // MARK: - Side scene (working / sleeping)

    // Working and sleeping are shown from the side: a cat sitting in profile at
    // the laptop. The lit screen is on the left (the cat looks left at it) and
    // the keyboard is in front, under two forepaws that tap the keys. The body
    // shows a clear head, chest, haunch, and curled tail. The keyboard is
    // layered between the body and the forepaws so the paws rest on the keys.
    // Sleeping slumps the loaf onto the desk, closes the eye, and dims the screen.
    private static func drawSideScene(sample: CatAnimationSample, context: CGContext) {
        let lying = sample.pose == .sleeping

        drawSideLaptopScreen(sample: sample, screen: screenState(for: sample), context: context)

        withBodyTransform(sample: sample, context: context) { context in
            drawSideTail(sample: sample, context: context)
            context.saveGState()
            if lying {
                // Slump the whole loaf down onto the desk to read as "asleep".
                context.translateBy(x: 64, y: 42)
                context.scaleBy(x: 1.04, y: 0.8)
                context.translateBy(x: -64, y: -42)
            }
            drawSideBody(sample: sample, context: context)
            drawSideHindLeg(sample: sample, context: context)
            drawSideHead(sample: sample, context: context)
            context.restoreGState()
        }

        drawSideLaptopKeyboard(sample: sample, context: context)

        withBodyTransform(sample: sample, context: context) { context in
            context.saveGState()
            if lying {
                context.translateBy(x: 64, y: 42)
                context.scaleBy(x: 1.04, y: 0.8)
                context.translateBy(x: -64, y: -42)
            }
            drawSideFrontPaws(sample: sample, context: context)
            context.restoreGState()
        }

        if lying {
            drawSleepMarks(sample: sample, context: context)
        }
    }

    private static func drawSideBody(sample: CatAnimationSample, context: CGContext) {
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 59, y: 27))
        body.addCurve(to: CGPoint(x: 49, y: 40), control1: CGPoint(x: 53, y: 30), control2: CGPoint(x: 49, y: 35))
        body.addCurve(to: CGPoint(x: 54, y: 55), control1: CGPoint(x: 49, y: 47), control2: CGPoint(x: 50, y: 52))
        body.addCurve(to: CGPoint(x: 64, y: 64), control1: CGPoint(x: 57, y: 60), control2: CGPoint(x: 60, y: 63))
        body.addCurve(to: CGPoint(x: 87, y: 62), control1: CGPoint(x: 72, y: 66), control2: CGPoint(x: 80, y: 65))
        body.addCurve(to: CGPoint(x: 103, y: 49), control1: CGPoint(x: 98, y: 60), control2: CGPoint(x: 103, y: 54))
        body.addCurve(to: CGPoint(x: 104, y: 35), control1: CGPoint(x: 105, y: 43), control2: CGPoint(x: 105, y: 38))
        body.addCurve(to: CGPoint(x: 93, y: 25), control1: CGPoint(x: 103, y: 29), control2: CGPoint(x: 99, y: 25))
        body.addCurve(to: CGPoint(x: 59, y: 27), control1: CGPoint(x: 82, y: 23), control2: CGPoint(x: 68, y: 23))
        body.closeSubpath()
        fillAndStroke(
            body,
            fill: Palette.fur,
            stroke: Palette.outline,
            sample: sample,
            lineWidth: Metrics.outlineWidth,
            context: context
        )

        let haunchShadow = CGPath(
            ellipseIn: CGRect(x: 76, y: 27, width: 23, height: 28),
            transform: nil
        )
        fill(haunchShadow, color: Palette.furShadow, sample: sample, alpha: 0.28, context: context)

        let chest = CGMutablePath()
        chest.move(to: CGPoint(x: 53, y: 33))
        chest.addCurve(to: CGPoint(x: 52, y: 52), control1: CGPoint(x: 49, y: 39), control2: CGPoint(x: 49, y: 47))
        chest.addCurve(to: CGPoint(x: 60, y: 58), control1: CGPoint(x: 55, y: 56), control2: CGPoint(x: 57, y: 58))
        chest.addCurve(to: CGPoint(x: 63, y: 38), control1: CGPoint(x: 64, y: 53), control2: CGPoint(x: 65, y: 43))
        chest.addCurve(to: CGPoint(x: 53, y: 33), control1: CGPoint(x: 60, y: 34), control2: CGPoint(x: 57, y: 32))
        chest.closeSubpath()
        fill(chest, color: Palette.highlight, sample: sample, alpha: 0.52, context: context)

        let stripes = CGMutablePath()
        stripes.move(to: CGPoint(x: 77, y: 58))
        stripes.addCurve(to: CGPoint(x: 84, y: 59), control1: CGPoint(x: 79, y: 60), control2: CGPoint(x: 82, y: 60))
        stripes.move(to: CGPoint(x: 86, y: 55))
        stripes.addCurve(to: CGPoint(x: 93, y: 54), control1: CGPoint(x: 88, y: 57), control2: CGPoint(x: 91, y: 56))
        stroke(stripes, color: Palette.markings, sample: sample, lineWidth: Metrics.detailWidth, context: context)
    }

    private static func drawSideHindLeg(sample: CatAnimationSample, context: CGContext) {
        let leg = CGMutablePath()
        leg.move(to: CGPoint(x: 81, y: 25))
        leg.addCurve(to: CGPoint(x: 69, y: 34), control1: CGPoint(x: 74, y: 26), control2: CGPoint(x: 69, y: 29))
        leg.addCurve(to: CGPoint(x: 78, y: 45), control1: CGPoint(x: 69, y: 40), control2: CGPoint(x: 72, y: 44))
        leg.addCurve(to: CGPoint(x: 94, y: 49), control1: CGPoint(x: 84, y: 50), control2: CGPoint(x: 91, y: 51))
        leg.addCurve(to: CGPoint(x: 101, y: 36), control1: CGPoint(x: 101, y: 46), control2: CGPoint(x: 103, y: 40))
        leg.addCurve(to: CGPoint(x: 92, y: 26), control1: CGPoint(x: 100, y: 30), control2: CGPoint(x: 97, y: 26))
        leg.addCurve(to: CGPoint(x: 81, y: 25), control1: CGPoint(x: 88, y: 25), control2: CGPoint(x: 84, y: 24))
        leg.closeSubpath()
        fillAndStroke(
            leg,
            fill: Palette.fur,
            stroke: Palette.outline,
            sample: sample,
            lineWidth: 2.4,
            context: context
        )
        let toes = CGMutablePath()
        toes.move(to: CGPoint(x: 76, y: 26))
        toes.addLine(to: CGPoint(x: 76.5, y: 29.5))
        toes.move(to: CGPoint(x: 81, y: 25.5))
        toes.addLine(to: CGPoint(x: 81.5, y: 29))
        stroke(toes, color: Palette.markings, sample: sample, lineWidth: 1.2, context: context)
    }

    private static func drawSideHead(sample: CatAnimationSample, context: CGContext) {
        context.saveGState()
        context.translateBy(
            x: CGFloat(sample.headOffsetX),
            y: CGFloat(sample.headOffsetY)
        )

        let earLift = CGFloat(sample.earOffset)

        // Ears sit high on the skull with wide bases, roughly as tall as they
        // are wide. The far ear is drawn first and shaded so the pair reads with
        // depth instead of as two spikes.
        let farEar = CGMutablePath()
        farEar.move(to: CGPoint(x: 48.5, y: 84.5))
        farEar.addLine(to: CGPoint(x: 49.5, y: 96.5 + earLift))
        farEar.addLine(to: CGPoint(x: 57.5, y: 88.5))
        farEar.closeSubpath()
        fillAndStroke(
            farEar,
            fill: Palette.furShadow,
            stroke: Palette.outline,
            sample: sample,
            lineWidth: Metrics.outlineWidth,
            context: context
        )

        let nearEar = CGMutablePath()
        nearEar.move(to: CGPoint(x: 58.5, y: 88))
        nearEar.addLine(to: CGPoint(x: 66.5, y: 97.5 + earLift * 0.85))
        nearEar.addLine(to: CGPoint(x: 70, y: 84))
        nearEar.closeSubpath()
        fillAndStroke(
            nearEar,
            fill: Palette.fur,
            stroke: Palette.outline,
            sample: sample,
            lineWidth: Metrics.outlineWidth,
            context: context
        )

        let innerEar = CGMutablePath()
        innerEar.move(to: CGPoint(x: 60.5, y: 87.8))
        innerEar.addLine(to: CGPoint(x: 65.8, y: 94))
        innerEar.addLine(to: CGPoint(x: 67.8, y: 85.5))
        innerEar.closeSubpath()
        fill(innerEar, color: Palette.cheeks, sample: sample, alpha: 0.6, context: context)

        // A rounded skull whose face front drops almost vertically from the brow
        // to the chin, so the muzzle barely projects. That short face is what
        // separates a cat from a rodent in profile; the previous long tapering
        // snout is what made this pose read as a rat.
        let head = CGMutablePath()
        head.move(to: CGPoint(x: 43.5, y: 75.5))
        head.addCurve(to: CGPoint(x: 47.5, y: 82.5), control1: CGPoint(x: 43.8, y: 78.5), control2: CGPoint(x: 45.3, y: 81))
        head.addCurve(to: CGPoint(x: 57.5, y: 89), control1: CGPoint(x: 50, y: 85.5), control2: CGPoint(x: 53.5, y: 89))
        head.addCurve(to: CGPoint(x: 69, y: 84), control1: CGPoint(x: 63.5, y: 89.5), control2: CGPoint(x: 67, y: 88))
        head.addCurve(to: CGPoint(x: 71.5, y: 74), control1: CGPoint(x: 71.5, y: 80.5), control2: CGPoint(x: 72.5, y: 77))
        head.addCurve(to: CGPoint(x: 66, y: 67), control1: CGPoint(x: 70.5, y: 70.5), control2: CGPoint(x: 69, y: 68))
        head.addCurve(to: CGPoint(x: 55, y: 69.5), control1: CGPoint(x: 62, y: 65.8), control2: CGPoint(x: 58.5, y: 68.8))
        head.addCurve(to: CGPoint(x: 46.5, y: 71.8), control1: CGPoint(x: 51.5, y: 70.3), control2: CGPoint(x: 48.5, y: 70.5))
        head.addCurve(to: CGPoint(x: 43.5, y: 75.5), control1: CGPoint(x: 44.5, y: 73), control2: CGPoint(x: 43.3, y: 74))
        head.closeSubpath()
        fillAndStroke(
            head,
            fill: Palette.fur,
            stroke: Palette.outline,
            sample: sample,
            lineWidth: Metrics.outlineWidth,
            context: context
        )

        let foreheadStripes = CGMutablePath()
        foreheadStripes.move(to: CGPoint(x: 56, y: 87.5))
        foreheadStripes.addCurve(to: CGPoint(x: 57, y: 81.5), control1: CGPoint(x: 57, y: 85), control2: CGPoint(x: 57.5, y: 83.5))
        foreheadStripes.move(to: CGPoint(x: 62.5, y: 87))
        foreheadStripes.addCurve(to: CGPoint(x: 63.5, y: 81), control1: CGPoint(x: 63.5, y: 84.5), control2: CGPoint(x: 64, y: 83))
        stroke(foreheadStripes, color: Palette.markings, sample: sample, lineWidth: 1.9, context: context)

        let eyeCenter = CGPoint(
            x: 52 + CGFloat(sample.eyeOffsetX),
            y: 79.5 + CGFloat(sample.eyeOffsetY)
        )
        if sample.pose == .sleeping {
            drawClosedEye(center: eyeCenter, sample: sample, context: context)
        } else {
            let eyeHeight = max(0.9, 5.2 * (1 - CGFloat(sample.blinkAmount)))
            drawOpenEye(center: eyeCenter, width: 5.0, height: eyeHeight, sample: sample, context: context)
            if sample.blinkAmount < 0.5 {
                let shine = CGPath(
                    ellipseIn: CGRect(
                        x: eyeCenter.x - 0.2,
                        y: eyeCenter.y + eyeHeight * 0.14,
                        width: 1.6,
                        height: 1.6
                    ),
                    transform: nil
                )
                fill(shine, color: Palette.screenHighlight, sample: sample, alpha: 0.9, context: context)
            }
        }

        let cheekAlpha: CGFloat = sample.pose == .broken ? 0.32 : 0.68
        let cheek = CGPath(ellipseIn: CGRect(x: 46.5, y: 73.5, width: 7, height: 3.5), transform: nil)
        fill(cheek, color: Palette.cheeks, sample: sample, alpha: cheekAlpha, context: context)

        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: 44, y: 77))
        nose.addCurve(to: CGPoint(x: 47.2, y: 75.6), control1: CGPoint(x: 45.6, y: 77.3), control2: CGPoint(x: 46.9, y: 76.6))
        nose.addCurve(to: CGPoint(x: 44, y: 74.5), control1: CGPoint(x: 46.6, y: 74.6), control2: CGPoint(x: 45, y: 74.3))
        nose.closeSubpath()
        fill(nose, color: Palette.outline, sample: sample, context: context)

        // Two whiskers only, and short: a long fan out of the muzzle rebuilds the
        // snout the new skull just removed.
        let mouthAndWhiskers = CGMutablePath()
        mouthAndWhiskers.move(to: CGPoint(x: 45.3, y: 74.4))
        mouthAndWhiskers.addCurve(to: CGPoint(x: 48, y: 72.3), control1: CGPoint(x: 45.6, y: 73.2), control2: CGPoint(x: 46.7, y: 72.4))
        mouthAndWhiskers.move(to: CGPoint(x: 46.5, y: 76.2))
        mouthAndWhiskers.addCurve(to: CGPoint(x: 34.5, y: 77), control1: CGPoint(x: 41, y: 77.2), control2: CGPoint(x: 37, y: 77.6))
        mouthAndWhiskers.move(to: CGPoint(x: 46, y: 73.6))
        mouthAndWhiskers.addCurve(to: CGPoint(x: 35.5, y: 70.6), control1: CGPoint(x: 41, y: 73), control2: CGPoint(x: 37.5, y: 72))
        stroke(mouthAndWhiskers, color: Palette.outline, sample: sample, lineWidth: 1.4, context: context)

        context.restoreGState()
    }

    private static func drawSideFrontPaws(sample: CatAnimationSample, context: CGContext) {
        // Two forelimbs reach forward onto the keys; the paws alternate typing.
        let farPaw = CGPoint(
            x: 50 + CGFloat(sample.leftPawOffsetX),
            y: 31 - CGFloat(sample.leftPawOffsetY) * 0.85
        )
        let nearPaw = CGPoint(
            x: 59 + CGFloat(sample.rightPawOffsetX),
            y: 30 - CGFloat(sample.rightPawOffsetY)
        )
        drawSideForelimb(shoulder: CGPoint(x: 57, y: 53), wrist: CGPoint(x: 52, y: 36), paw: farPaw, sample: sample, context: context)
        drawSideForelimb(shoulder: CGPoint(x: 63, y: 51), wrist: CGPoint(x: 60, y: 34), paw: nearPaw, sample: sample, context: context)
    }

    // A furry forelimb (outline + fur pass, like the tail) ending in a paw that
    // rests on the keys. The paw center moves with the planner's tap offset.
    private static func drawSideForelimb(
        shoulder: CGPoint,
        wrist: CGPoint,
        paw: CGPoint,
        sample: CatAnimationSample,
        context: CGContext
    ) {
        let limb = CGMutablePath()
        limb.move(to: shoulder)
        limb.addCurve(
            to: wrist,
            control1: CGPoint(x: shoulder.x - 2, y: shoulder.y - 8),
            control2: CGPoint(x: wrist.x + 1, y: wrist.y + 6)
        )
        stroke(limb, color: Palette.outline, sample: sample, lineWidth: 12, context: context)
        stroke(limb, color: Palette.fur, sample: sample, lineWidth: 8.5, context: context)

        let pawShape = CGPath(
            ellipseIn: CGRect(x: paw.x - 6.5, y: paw.y - 4, width: 13, height: 8),
            transform: nil
        )
        fillAndStroke(pawShape, fill: Palette.fur, stroke: Palette.outline, sample: sample, lineWidth: 2.15, context: context)

        let toes = CGMutablePath()
        toes.move(to: CGPoint(x: paw.x - 2.2, y: paw.y - 2.6))
        toes.addLine(to: CGPoint(x: paw.x - 2.2, y: paw.y + 0.6))
        toes.move(to: CGPoint(x: paw.x + 1.8, y: paw.y - 2.6))
        toes.addLine(to: CGPoint(x: paw.x + 1.8, y: paw.y + 0.6))
        stroke(toes, color: Palette.markings, sample: sample, lineWidth: 1.1, context: context)
    }

    private static func drawSideTail(sample: CatAnimationSample, context: CGContext) {
        let wag = CGFloat(sample.tailOffset)
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: 95, y: 40))
        tail.addCurve(
            to: CGPoint(x: 106, y: 54 + wag),
            control1: CGPoint(x: 105, y: 37 + wag),
            control2: CGPoint(x: 107, y: 48 + wag)
        )
        tail.addCurve(
            to: CGPoint(x: 97, y: 58 + wag * 0.4),
            control1: CGPoint(x: 105, y: 60 + wag),
            control2: CGPoint(x: 100, y: 62 + wag * 0.6)
        )
        stroke(tail, color: Palette.outline, sample: sample, lineWidth: 15, context: context)
        stroke(tail, color: Palette.fur, sample: sample, lineWidth: 10, context: context)

        let stripe = CGMutablePath()
        stripe.move(to: CGPoint(x: 100, y: 49 + wag))
        stripe.addCurve(
            to: CGPoint(x: 105, y: 55 + wag),
            control1: CGPoint(x: 102, y: 51 + wag),
            control2: CGPoint(x: 104, y: 53 + wag)
        )
        stroke(stripe, color: Palette.markings, sample: sample, lineWidth: 2.2, context: context)
    }

    private static func drawSideLaptopScreen(
        sample: CatAnimationSample,
        screen: LaptopScreen,
        context: CGContext
    ) {
        let lid = Metrics.sideLid

        // A dark rim down the outer edge gives the lid its thickness.
        let edge = quad(
            CGPoint(x: lid.bottomLeft.x - 2.4, y: lid.bottomLeft.y - 0.6),
            CGPoint(x: lid.topLeft.x - 2.4, y: lid.topLeft.y - 0.6),
            lid.topLeft,
            lid.bottomLeft
        )
        fillAndStroke(
            edge,
            fill: Palette.screenEdge,
            stroke: Palette.outline,
            sample: sample,
            lineWidth: 1.6,
            context: context
        )

        let bezel = quad(lid.bottomLeft, lid.bottomRight, lid.topRight, lid.topLeft)
        fillAndStroke(
            bezel,
            fill: Palette.screenBezel,
            stroke: Palette.outline,
            sample: sample,
            lineWidth: 2.2,
            context: context
        )

        let inner = lid.inset(by: Metrics.sidePanelInset)
        let panel = quad(inner.bottomLeft, inner.bottomRight, inner.topRight, inner.topLeft)
        switch screen {
        case .on, .dim:
            let base: CGFloat = screen == .on ? 1.0 : 0.3
            fill(panel, color: IllustrationColor(sample.accent), sample: sample, alpha: base, context: context)
            drawSideScreenContent(sample: sample, screen: screen, context: context)
            let bloom = CGPath(ellipseIn: CGRect(x: 29, y: 40, width: 11, height: 9), transform: nil)
            fill(
                bloom,
                color: Palette.screenHighlight,
                sample: sample,
                alpha: 0.26 * CGFloat(sample.screenGlow),
                context: context
            )
        case .off:
            fill(panel, color: Palette.screenOff, sample: sample, context: context)
        }

        let camera = CGPath(
            ellipseIn: CGRect(x: 34.2, y: 54.3, width: 2.0, height: 1.3),
            transform: nil
        )
        fill(camera, color: Palette.outline, sample: sample, alpha: 0.8, context: context)
    }

    private static func drawSideScreenContent(
        sample: CatAnimationSample,
        screen: LaptopScreen,
        context: CGContext
    ) {
        let alpha: CGFloat = screen == .on ? 0.38 : 0.16
        let code = CGMutablePath()
        code.move(to: CGPoint(x: 28.5, y: 48.5))
        code.addLine(to: CGPoint(x: 43.5, y: 46.6))
        code.move(to: CGPoint(x: 29, y: 44.5))
        code.addLine(to: CGPoint(x: 45, y: 42.5))
        code.move(to: CGPoint(x: 29.5, y: 40.5))
        code.addLine(to: CGPoint(x: 39, y: 39.3))
        code.move(to: CGPoint(x: 30, y: 36.6))
        code.addLine(to: CGPoint(x: 44, y: 34.8))
        stroke(code, color: Palette.screenHighlight, sample: sample, lineWidth: 1.25, alpha: alpha, context: context)

        let prompt = CGPath(
            ellipseIn: CGRect(x: 26.4, y: 47.6, width: 1.7, height: 1.7),
            transform: nil
        )
        fill(prompt, color: Palette.screenHighlight, sample: sample, alpha: alpha, context: context)
    }

    private static func drawSideLaptopKeyboard(sample: CatAnimationSample, context: CGContext) {
        let keyboard = quad(
            CGPoint(x: 26, y: 34),
            CGPoint(x: 68, y: 29),
            CGPoint(x: 76, y: 20),
            CGPoint(x: 35, y: 24)
        )
        fillAndStroke(
            keyboard,
            fill: Palette.keyboardBase,
            stroke: Palette.outline,
            sample: sample,
            lineWidth: 2.2,
            context: context
        )

        let frontLip = quad(
            CGPoint(x: 35, y: 24),
            CGPoint(x: 76, y: 20),
            CGPoint(x: 73.5, y: 17.5),
            CGPoint(x: 37.5, y: 21)
        )
        fillAndStroke(
            frontLip,
            fill: Palette.keyboardShade,
            stroke: Palette.outline,
            sample: sample,
            lineWidth: 1.5,
            context: context
        )

        let keys = CGMutablePath()
        keys.move(to: CGPoint(x: 33, y: 31.5))
        keys.addLine(to: CGPoint(x: 65, y: 27.7))
        keys.move(to: CGPoint(x: 35.5, y: 28.5))
        keys.addLine(to: CGPoint(x: 68, y: 24.7))
        keys.move(to: CGPoint(x: 38, y: 25.5))
        keys.addLine(to: CGPoint(x: 70.5, y: 21.7))
        stroke(keys, color: Palette.keyboardShade, sample: sample, lineWidth: 1.15, context: context)

        let keyGaps = CGMutablePath()
        for x in stride(from: 42, through: 62, by: 5) {
            keyGaps.move(to: CGPoint(x: CGFloat(x), y: 30.4))
            keyGaps.addLine(to: CGPoint(x: CGFloat(x) + 1.2, y: 24.5))
        }
        stroke(keyGaps, color: Palette.keyboardHighlight, sample: sample, lineWidth: 0.8, alpha: 0.55, context: context)

        let trackpad = quad(
            CGPoint(x: 57, y: 23.5),
            CGPoint(x: 68.5, y: 22.2),
            CGPoint(x: 66.5, y: 20.3),
            CGPoint(x: 55.5, y: 21.6)
        )
        stroke(trackpad, color: Palette.keyboardHighlight, sample: sample, lineWidth: 0.9, alpha: 0.65, context: context)
    }

    // MARK: - Grabbed scene (dragging)

    // Dragging drops the laptop and lifts the cat by the scruff: the body is
    // stretched downward, the paws dangle, the eyes go wide, and a small wiggle
    // above the head marks where it is held.
    private static func drawGrabbedScene(sample: CatAnimationSample, context: CGContext) {
        withBodyTransform(sample: sample, context: context) { context in
            context.saveGState()
            context.translateBy(x: 64, y: 82)
            context.scaleBy(x: 0.95, y: 1.1)
            context.translateBy(x: -64, y: -82)
            drawGrabbedTail(sample: sample, context: context)
            drawBody(sample: sample, context: context)
            drawHead(sample: sample, context: context)
            drawGrabbedPaws(sample: sample, context: context)
            context.restoreGState()
        }
        drawScruffWiggle(sample: sample, context: context)
    }

    private static func drawGrabbedTail(sample: CatAnimationSample, context: CGContext) {
        // A tail drooping down from the rump while the cat hangs.
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: 88, y: 44))
        tail.addCurve(
            to: CGPoint(x: 96, y: 18),
            control1: CGPoint(x: 100, y: 38),
            control2: CGPoint(x: 100, y: 24)
        )
        stroke(tail, color: Palette.outline, sample: sample, lineWidth: 16, context: context)
        stroke(tail, color: Palette.fur, sample: sample, lineWidth: 11, context: context)
    }

    private static func drawGrabbedPaws(sample: CatAnimationSample, context: CGContext) {
        let left = CGPoint(
            x: 54 + CGFloat(sample.leftPawOffsetX),
            y: 24 - CGFloat(sample.leftPawOffsetY)
        )
        let right = CGPoint(
            x: 74 + CGFloat(sample.rightPawOffsetX),
            y: 24 - CGFloat(sample.rightPawOffsetY)
        )
        drawPaw(center: left, sample: sample, context: context)
        drawPaw(center: right, sample: sample, context: context)
    }

    private static func drawScruffWiggle(sample: CatAnimationSample, context: CGContext) {
        let wiggle = CGMutablePath()
        wiggle.move(to: CGPoint(x: 58, y: 112))
        wiggle.addCurve(to: CGPoint(x: 64, y: 113.5), control1: CGPoint(x: 60, y: 114), control2: CGPoint(x: 62, y: 111.5))
        wiggle.addCurve(to: CGPoint(x: 70, y: 112), control1: CGPoint(x: 66, y: 113.5), control2: CGPoint(x: 68, y: 110.5))
        stroke(wiggle, color: Palette.markings, sample: sample, lineWidth: 1.6, context: context)
    }

    // MARK: - Overhead glyphs

    private static func drawSleepMarks(sample: CatAnimationSample, context: CGContext) {
        // Drifting "Zzz" rising up and to the right of the sleeping head.
        let z = CGMutablePath()
        addSleepGlyph(to: z, origin: CGPoint(x: 64, y: 84), size: 7)
        addSleepGlyph(to: z, origin: CGPoint(x: 74, y: 93), size: 5)
        addSleepGlyph(to: z, origin: CGPoint(x: 82, y: 100), size: 3.5)
        stroke(z, color: Palette.markings, sample: sample, lineWidth: 1.6, context: context)
    }

    private static func addSleepGlyph(
        to path: CGMutablePath,
        origin: CGPoint,
        size: CGFloat
    ) {
        path.move(to: CGPoint(x: origin.x, y: origin.y + size))
        path.addLine(to: CGPoint(x: origin.x + size, y: origin.y + size))
        path.addLine(to: CGPoint(x: origin.x, y: origin.y))
        path.addLine(to: CGPoint(x: origin.x + size, y: origin.y))
    }

    private static func drawThinkMarks(sample: CatAnimationSample, context: CGContext) {
        // Rising "???" while the cat turns to us and asks what we want. They
        // climb past the head's top-right corner: a grown cat fills the canvas,
        // so that diagonal is the only space left inside the safe bounds. They
        // also carry the model accent, which the hover scene otherwise loses
        // along with the laptop screen.
        let specs: [(CGPoint, CGFloat)] = [
            (CGPoint(x: 97, y: 98), 6),
            (CGPoint(x: 105, y: 107), 5),
            (CGPoint(x: 112, y: 115), 4)
        ]
        let accent = IllustrationColor(sample.accent)
        let hooks = CGMutablePath()
        for spec in specs {
            addQuestionHook(to: hooks, origin: spec.0, size: spec.1)
        }
        stroke(hooks, color: accent, sample: sample, lineWidth: 2.0, context: context)

        for spec in specs {
            let radius = spec.1 * 0.17
            let dot = CGPath(
                ellipseIn: CGRect(
                    x: spec.0.x + spec.1 * 0.5 - radius,
                    y: spec.0.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ),
                transform: nil
            )
            fill(dot, color: accent, sample: sample, context: context)
        }
    }

    // Adds the hook and stem of a question mark (the dot is filled separately).
    private static func addQuestionHook(
        to path: CGMutablePath,
        origin: CGPoint,
        size: CGFloat
    ) {
        path.move(to: CGPoint(x: origin.x, y: origin.y + size * 0.55))
        path.addCurve(
            to: CGPoint(x: origin.x + size, y: origin.y + size * 0.55),
            control1: CGPoint(x: origin.x + size * 0.02, y: origin.y + size * 1.15),
            control2: CGPoint(x: origin.x + size * 0.98, y: origin.y + size * 1.15)
        )
        path.addCurve(
            to: CGPoint(x: origin.x + size * 0.5, y: origin.y + size * 0.22),
            control1: CGPoint(x: origin.x + size, y: origin.y + size * 0.3),
            control2: CGPoint(x: origin.x + size * 0.5, y: origin.y + size * 0.42)
        )
    }

    // MARK: - Shared cat parts (front / grabbed)

    private static func drawTail(sample: CatAnimationSample, context: CGContext) {
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: 88, y: 45))
        tail.addCurve(
            to: CGPoint(x: 106, y: 27 + CGFloat(sample.tailOffset)),
            control1: CGPoint(x: 105, y: 48 + CGFloat(sample.tailOffset)),
            control2: CGPoint(x: 113, y: 35 + CGFloat(sample.tailOffset))
        )
        tail.addCurve(
            to: CGPoint(x: 98, y: 20 + CGFloat(sample.tailOffset) * 0.35),
            control1: CGPoint(x: 105, y: 22 + CGFloat(sample.tailOffset)),
            control2: CGPoint(x: 101, y: 20 + CGFloat(sample.tailOffset) * 0.6)
        )
        stroke(
            tail,
            color: Palette.outline,
            sample: sample,
            lineWidth: 16,
            context: context
        )
        stroke(
            tail,
            color: Palette.fur,
            sample: sample,
            lineWidth: 11,
            context: context
        )

        let stripe = CGMutablePath()
        stripe.move(to: CGPoint(x: 103, y: 35 + CGFloat(sample.tailOffset)))
        stripe.addCurve(
            to: CGPoint(x: 109, y: 31 + CGFloat(sample.tailOffset)),
            control1: CGPoint(x: 106, y: 35 + CGFloat(sample.tailOffset)),
            control2: CGPoint(x: 108, y: 33 + CGFloat(sample.tailOffset))
        )
        stroke(
            stripe,
            color: Palette.markings,
            sample: sample,
            lineWidth: 2.2,
            context: context
        )
    }

    private static func drawBody(sample: CatAnimationSample, context: CGContext) {
        let roundness = CGFloat(sample.bodyRoundness) * 18
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 40, y: 29))
        body.addCurve(
            to: CGPoint(x: 30, y: 59),
            control1: CGPoint(x: 31 - roundness * 0.15, y: 36),
            control2: CGPoint(x: 27 - roundness * 0.2, y: 49)
        )
        body.addCurve(
            to: CGPoint(x: 40, y: 83),
            control1: CGPoint(x: 31, y: 71 + roundness * 0.1),
            control2: CGPoint(x: 35, y: 78 + roundness * 0.15)
        )
        body.addCurve(
            to: CGPoint(x: 88, y: 81),
            control1: CGPoint(x: 52, y: 92 + roundness * 0.2),
            control2: CGPoint(x: 77, y: 91 + roundness * 0.2)
        )
        body.addCurve(
            to: CGPoint(x: 99, y: 55),
            control1: CGPoint(x: 97 + roundness * 0.15, y: 75),
            control2: CGPoint(x: 102 + roundness * 0.15, y: 64)
        )
        body.addCurve(
            to: CGPoint(x: 88, y: 32),
            control1: CGPoint(x: 98, y: 43),
            control2: CGPoint(x: 95, y: 35)
        )
        body.addCurve(
            to: CGPoint(x: 40, y: 29),
            control1: CGPoint(x: 75, y: 24 - roundness * 0.1),
            control2: CGPoint(x: 51, y: 23 - roundness * 0.1)
        )
        body.closeSubpath()
        fillAndStroke(
            body,
            fill: Palette.fur,
            stroke: Palette.outline,
            sample: sample,
            lineWidth: Metrics.outlineWidth,
            context: context
        )

        let chest = CGMutablePath()
        chest.move(to: CGPoint(x: 47, y: 42))
        chest.addCurve(
            to: CGPoint(x: 56, y: 30),
            control1: CGPoint(x: 46, y: 35),
            control2: CGPoint(x: 50, y: 30)
        )
        chest.addCurve(
            to: CGPoint(x: 66, y: 42),
            control1: CGPoint(x: 63, y: 31),
            control2: CGPoint(x: 67, y: 35)
        )
        chest.addCurve(
            to: CGPoint(x: 47, y: 42),
            control1: CGPoint(x: 59, y: 39),
            control2: CGPoint(x: 54, y: 45)
        )
        chest.closeSubpath()
        fill(chest, color: Palette.highlight, sample: sample, alpha: 0.68, context: context)

        let sideMarks = CGMutablePath()
        sideMarks.move(to: CGPoint(x: 87, y: 61))
        sideMarks.addCurve(to: CGPoint(x: 94, y: 58), control1: CGPoint(x: 90, y: 62), control2: CGPoint(x: 92, y: 61))
        sideMarks.move(to: CGPoint(x: 87, y: 54))
        sideMarks.addCurve(to: CGPoint(x: 94, y: 51), control1: CGPoint(x: 90, y: 55), control2: CGPoint(x: 92, y: 54))
        stroke(sideMarks, color: Palette.markings, sample: sample, lineWidth: Metrics.detailWidth, context: context)
    }

    private static func drawHead(sample: CatAnimationSample, context: CGContext) {
        context.saveGState()
        context.translateBy(
            x: CGFloat(sample.headOffsetX),
            y: CGFloat(sample.headOffsetY)
        )

        let earLift = CGFloat(sample.earOffset)
        let head = CGMutablePath()
        head.move(to: CGPoint(x: 35, y: 69))
        head.addCurve(to: CGPoint(x: 38, y: 94), control1: CGPoint(x: 31, y: 79), control2: CGPoint(x: 33, y: 88))
        head.addCurve(to: CGPoint(x: 40, y: 108 + earLift), control1: CGPoint(x: 37, y: 100), control2: CGPoint(x: 37, y: 105 + earLift))
        head.addCurve(to: CGPoint(x: 53, y: 101), control1: CGPoint(x: 45, y: 106 + earLift), control2: CGPoint(x: 49, y: 103))
        head.addCurve(to: CGPoint(x: 74, y: 102), control1: CGPoint(x: 60, y: 104), control2: CGPoint(x: 68, y: 104))
        head.addCurve(to: CGPoint(x: 89, y: 109 - earLift * 0.35), control1: CGPoint(x: 80, y: 104), control2: CGPoint(x: 84, y: 107 - earLift * 0.2))
        head.addCurve(to: CGPoint(x: 90, y: 92), control1: CGPoint(x: 91, y: 103), control2: CGPoint(x: 92, y: 97))
        head.addCurve(to: CGPoint(x: 93, y: 73), control1: CGPoint(x: 96, y: 86), control2: CGPoint(x: 96, y: 79))
        head.addCurve(to: CGPoint(x: 82, y: 60), control1: CGPoint(x: 90, y: 67), control2: CGPoint(x: 87, y: 63))
        head.addCurve(to: CGPoint(x: 47, y: 60), control1: CGPoint(x: 72, y: 55), control2: CGPoint(x: 56, y: 55))
        head.addCurve(to: CGPoint(x: 35, y: 69), control1: CGPoint(x: 41, y: 62), control2: CGPoint(x: 37, y: 65))
        head.closeSubpath()
        fillAndStroke(
            head,
            fill: Palette.fur,
            stroke: Palette.outline,
            sample: sample,
            lineWidth: Metrics.outlineWidth,
            context: context
        )

        drawHeadMarkings(sample: sample, context: context)
        drawFace(sample: sample, context: context)
        context.restoreGState()
    }

    private static func drawHeadMarkings(sample: CatAnimationSample, context: CGContext) {
        let markings = CGMutablePath()
        markings.move(to: CGPoint(x: 58, y: 99))
        markings.addCurve(to: CGPoint(x: 57, y: 92), control1: CGPoint(x: 56, y: 96), control2: CGPoint(x: 56, y: 94))
        markings.move(to: CGPoint(x: 65, y: 101))
        markings.addCurve(to: CGPoint(x: 65, y: 93), control1: CGPoint(x: 64, y: 98), control2: CGPoint(x: 64, y: 96))
        markings.move(to: CGPoint(x: 72, y: 99))
        markings.addCurve(to: CGPoint(x: 73, y: 92), control1: CGPoint(x: 74, y: 96), control2: CGPoint(x: 74, y: 94))
        stroke(markings, color: Palette.markings, sample: sample, lineWidth: Metrics.detailWidth, context: context)
    }

    private static func drawFace(sample: CatAnimationSample, context: CGContext) {
        let eyeShift = CGPoint(
            x: CGFloat(sample.eyeOffsetX),
            y: CGFloat(sample.eyeOffsetY)
        )
        let leftEye = CGPoint(x: 53 + eyeShift.x, y: 79 + eyeShift.y)
        let rightEye = CGPoint(x: 76 + eyeShift.x, y: 79 + eyeShift.y)

        switch sample.pose {
        case .sleeping:
            drawClosedEye(center: leftEye, sample: sample, context: context)
            drawClosedEye(center: rightEye, sample: sample, context: context)
        case .broken:
            drawBrokenEyes(left: leftEye, right: rightEye, sample: sample, context: context)
        case .startled:
            drawOpenEye(center: leftEye, width: 4.8, height: 6.4, sample: sample, context: context)
            drawOpenEye(center: rightEye, width: 4.8, height: 6.4, sample: sample, context: context)
        case .dragging:
            // Wide, round "picked up" eyes.
            drawOpenEye(center: leftEye, width: 5.6, height: 6.2, sample: sample, context: context)
            drawOpenEye(center: rightEye, width: 5.6, height: 6.2, sample: sample, context: context)
        case .active, .hovering:
            let eyeHeight = max(0.8, 4.8 * (1 - CGFloat(sample.blinkAmount)))
            drawOpenEye(center: leftEye, width: 3.8, height: eyeHeight, sample: sample, context: context)
            drawOpenEye(center: rightEye, width: 3.8, height: eyeHeight, sample: sample, context: context)
        }

        let muzzle = CGPath(ellipseIn: CGRect(x: 57, y: 67, width: 15, height: 10), transform: nil)
        fill(muzzle, color: Palette.highlight, sample: sample, alpha: 0.7, context: context)

        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: 62.2, y: 73.5))
        nose.addCurve(to: CGPoint(x: 66.8, y: 73.5), control1: CGPoint(x: 63.3, y: 74.8), control2: CGPoint(x: 65.7, y: 74.8))
        nose.addCurve(to: CGPoint(x: 64.5, y: 71.4), control1: CGPoint(x: 66.3, y: 72.2), control2: CGPoint(x: 65.4, y: 71.5))
        nose.addCurve(to: CGPoint(x: 62.2, y: 73.5), control1: CGPoint(x: 63.6, y: 71.5), control2: CGPoint(x: 62.7, y: 72.2))
        nose.closeSubpath()
        fill(nose, color: Palette.outline, sample: sample, context: context)

        let mouthAndWhiskers = CGMutablePath()
        mouthAndWhiskers.move(to: CGPoint(x: 64.5, y: 71.7))
        mouthAndWhiskers.addCurve(to: CGPoint(x: 60.5, y: 69), control1: CGPoint(x: 64.2, y: 69.8), control2: CGPoint(x: 62.3, y: 68.8))
        mouthAndWhiskers.move(to: CGPoint(x: 64.5, y: 71.7))
        mouthAndWhiskers.addCurve(to: CGPoint(x: 68.5, y: 69), control1: CGPoint(x: 64.8, y: 69.8), control2: CGPoint(x: 66.7, y: 68.8))
        mouthAndWhiskers.move(to: CGPoint(x: 48, y: 70))
        mouthAndWhiskers.addCurve(to: CGPoint(x: 36, y: 72), control1: CGPoint(x: 43, y: 72), control2: CGPoint(x: 39, y: 72))
        mouthAndWhiskers.move(to: CGPoint(x: 48, y: 66.5))
        mouthAndWhiskers.addCurve(to: CGPoint(x: 37, y: 64), control1: CGPoint(x: 43, y: 66), control2: CGPoint(x: 40, y: 65))
        mouthAndWhiskers.move(to: CGPoint(x: 81, y: 70))
        mouthAndWhiskers.addCurve(to: CGPoint(x: 93, y: 72), control1: CGPoint(x: 86, y: 72), control2: CGPoint(x: 90, y: 72))
        mouthAndWhiskers.move(to: CGPoint(x: 81, y: 66.5))
        mouthAndWhiskers.addCurve(to: CGPoint(x: 92, y: 64), control1: CGPoint(x: 86, y: 66), control2: CGPoint(x: 89, y: 65))
        stroke(mouthAndWhiskers, color: Palette.outline, sample: sample, lineWidth: 1.65, context: context)

        let cheekAlpha: CGFloat = sample.pose == .broken ? 0.32 : 0.72
        let leftCheek = CGPath(ellipseIn: CGRect(x: 43, y: 68, width: 7.5, height: 3.8), transform: nil)
        let rightCheek = CGPath(ellipseIn: CGRect(x: 78.5, y: 68, width: 7.5, height: 3.8), transform: nil)
        fill(leftCheek, color: Palette.cheeks, sample: sample, alpha: cheekAlpha, context: context)
        fill(rightCheek, color: Palette.cheeks, sample: sample, alpha: cheekAlpha, context: context)
    }

    private static func drawOpenEye(
        center: CGPoint,
        width: CGFloat,
        height: CGFloat,
        sample: CatAnimationSample,
        context: CGContext
    ) {
        let eye = CGPath(
            ellipseIn: CGRect(
                x: center.x - width / 2,
                y: center.y - height / 2,
                width: width,
                height: height
            ),
            transform: nil
        )
        fill(eye, color: Palette.outline, sample: sample, context: context)
    }

    private static func drawClosedEye(
        center: CGPoint,
        sample: CatAnimationSample,
        context: CGContext
    ) {
        let eye = CGMutablePath()
        eye.move(to: CGPoint(x: center.x - 3, y: center.y + 0.8))
        eye.addCurve(
            to: CGPoint(x: center.x + 3, y: center.y + 0.8),
            control1: CGPoint(x: center.x - 1.5, y: center.y - 1.4),
            control2: CGPoint(x: center.x + 1.5, y: center.y - 1.4)
        )
        stroke(eye, color: Palette.outline, sample: sample, lineWidth: 1.8, context: context)
    }

    private static func drawBrokenEyes(
        left: CGPoint,
        right: CGPoint,
        sample: CatAnimationSample,
        context: CGContext
    ) {
        let eyes = CGMutablePath()
        eyes.move(to: CGPoint(x: left.x - 2.3, y: left.y - 2.3))
        eyes.addLine(to: CGPoint(x: left.x + 2.3, y: left.y + 2.3))
        eyes.move(to: CGPoint(x: left.x - 2.3, y: left.y + 2.3))
        eyes.addLine(to: CGPoint(x: left.x + 2.3, y: left.y - 2.3))
        eyes.move(to: CGPoint(x: right.x - 3, y: right.y + 0.8))
        eyes.addCurve(
            to: CGPoint(x: right.x + 3, y: right.y - 0.5),
            control1: CGPoint(x: right.x - 0.8, y: right.y - 1.3),
            control2: CGPoint(x: right.x + 1.2, y: right.y - 1.5)
        )
        stroke(eyes, color: Palette.outline, sample: sample, lineWidth: 1.9, context: context)
    }

    private static func drawPaws(sample: CatAnimationSample, context: CGContext) {
        let leftCenter = CGPoint(
            x: 54 + CGFloat(sample.leftPawOffsetX),
            y: 30 - CGFloat(sample.leftPawOffsetY)
        )
        let rightCenter = CGPoint(
            x: 74 + CGFloat(sample.rightPawOffsetX),
            y: 30 - CGFloat(sample.rightPawOffsetY)
        )
        drawPaw(center: leftCenter, sample: sample, context: context)
        drawPaw(center: rightCenter, sample: sample, context: context)
    }

    private static func drawPaw(
        center: CGPoint,
        sample: CatAnimationSample,
        context: CGContext
    ) {
        let paw = CGPath(
            roundedRect: CGRect(x: center.x - 8, y: center.y - 5.5, width: 16, height: 11),
            cornerWidth: 5.5,
            cornerHeight: 5.5,
            transform: nil
        )
        fillAndStroke(
            paw,
            fill: Palette.fur,
            stroke: Palette.outline,
            sample: sample,
            lineWidth: 2.15,
            context: context
        )

        let toes = CGMutablePath()
        toes.move(to: CGPoint(x: center.x - 2, y: center.y - 1.7))
        toes.addLine(to: CGPoint(x: center.x - 2, y: center.y + 1.2))
        toes.move(to: CGPoint(x: center.x + 2, y: center.y - 1.7))
        toes.addLine(to: CGPoint(x: center.x + 2, y: center.y + 1.2))
        stroke(toes, color: Palette.markings, sample: sample, lineWidth: 1.15, context: context)
    }

    // MARK: - Drawing helpers

    private static func quad(
        _ a: CGPoint,
        _ b: CGPoint,
        _ c: CGPoint,
        _ d: CGPoint
    ) -> CGPath {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        path.addLine(to: c)
        path.addLine(to: d)
        path.closeSubpath()
        return path
    }

    private static func fillAndStroke(
        _ path: CGPath,
        fill fillColor: IllustrationColor,
        stroke strokeColor: IllustrationColor,
        sample: CatAnimationSample,
        lineWidth: CGFloat,
        context: CGContext
    ) {
        context.addPath(path)
        context.setFillColor(fillColor.cgColor(desaturation: sample.desaturation))
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(strokeColor.cgColor(desaturation: sample.desaturation))
        context.setLineWidth(lineWidth)
        context.strokePath()
    }

    private static func fill(
        _ path: CGPath,
        color: IllustrationColor,
        sample: CatAnimationSample,
        alpha: CGFloat = 1,
        context: CGContext
    ) {
        context.addPath(path)
        context.setFillColor(color.cgColor(desaturation: sample.desaturation, alphaMultiplier: alpha))
        context.fillPath()
    }

    private static func stroke(
        _ path: CGPath,
        color: IllustrationColor,
        sample: CatAnimationSample,
        lineWidth: CGFloat,
        alpha: CGFloat = 1,
        context: CGContext
    ) {
        context.addPath(path)
        context.setStrokeColor(color.cgColor(desaturation: sample.desaturation, alphaMultiplier: alpha))
        context.setLineWidth(lineWidth)
        context.strokePath()
    }
}

private struct IllustrationColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    init(hex: UInt32) {
        red = CGFloat((hex >> 16) & 0xFF) / 255
        green = CGFloat((hex >> 8) & 0xFF) / 255
        blue = CGFloat(hex & 0xFF) / 255
        alpha = 1
    }

    init(_ color: PetColor) {
        red = CGFloat(color.r) / 255
        green = CGFloat(color.g) / 255
        blue = CGFloat(color.b) / 255
        alpha = CGFloat(color.a) / 255
    }

    func cgColor(
        desaturation: Double,
        alphaMultiplier: CGFloat = 1
    ) -> CGColor {
        let amount = CGFloat(desaturation)
        let luminance = red * 0.299 + green * 0.587 + blue * 0.114
        return CGColor(
            red: red + (luminance - red) * amount,
            green: green + (luminance - green) * amount,
            blue: blue + (luminance - blue) * amount,
            alpha: alpha * alphaMultiplier
        )
    }
}

#endif
