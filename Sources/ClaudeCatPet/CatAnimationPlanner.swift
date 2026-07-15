import Foundation

public enum CatPose: Equatable {
    case active
    case sleeping
    case broken
    case hovering
    case startled
    case dragging
}

// Platform-neutral description of one animation frame for the illustrated cat.
// All offsets are expressed in the renderer's 128-unit canvas space. A positive
// paw Y offset moves the paw down toward the keyboard (a keypress); `screenGlow`
// is the laptop screen brightness in 0...1 (0 = off, as in the broken state).
public struct CatAnimationSample: Equatable {
    public let clampedStage: Int
    public let pose: CatPose
    public let bodyScale: Double
    public let bodyRoundness: Double
    public let bodyBreath: Double
    public let headOffsetX: Double
    public let headOffsetY: Double
    public let eyeOffsetX: Double
    public let eyeOffsetY: Double
    public let earOffset: Double
    public let tailOffset: Double
    public let leftPawOffsetX: Double
    public let leftPawOffsetY: Double
    public let rightPawOffsetX: Double
    public let rightPawOffsetY: Double
    public let blinkAmount: Double
    public let screenGlow: Double
    public let accent: PetColor
    public let desaturation: Double
    public let decorativeMotionEnabled: Bool

    public init(
        clampedStage: Int,
        pose: CatPose,
        bodyScale: Double,
        bodyRoundness: Double,
        bodyBreath: Double,
        headOffsetX: Double,
        headOffsetY: Double,
        eyeOffsetX: Double,
        eyeOffsetY: Double,
        earOffset: Double,
        tailOffset: Double,
        leftPawOffsetX: Double,
        leftPawOffsetY: Double,
        rightPawOffsetX: Double,
        rightPawOffsetY: Double,
        blinkAmount: Double,
        screenGlow: Double,
        accent: PetColor,
        desaturation: Double,
        decorativeMotionEnabled: Bool
    ) {
        self.clampedStage = clampedStage
        self.pose = pose
        self.bodyScale = bodyScale
        self.bodyRoundness = bodyRoundness
        self.bodyBreath = bodyBreath
        self.headOffsetX = headOffsetX
        self.headOffsetY = headOffsetY
        self.eyeOffsetX = eyeOffsetX
        self.eyeOffsetY = eyeOffsetY
        self.earOffset = earOffset
        self.tailOffset = tailOffset
        self.leftPawOffsetX = leftPawOffsetX
        self.leftPawOffsetY = leftPawOffsetY
        self.rightPawOffsetX = rightPawOffsetX
        self.rightPawOffsetY = rightPawOffsetY
        self.blinkAmount = blinkAmount
        self.screenGlow = screenGlow
        self.accent = accent
        self.desaturation = desaturation
        self.decorativeMotionEnabled = decorativeMotionEnabled
    }
}

public enum CatAnimationPlanner {
    private enum Constants {
        static let stageCount = 6
        static let minimumBodyScale = 0.94
        static let bodyScaleStep = 0.032
        static let bodyRoundnessStep = 0.018
        static let minimumFrameInterval = 0.7
        static let maximumFrameInterval = 2.5
        static let minimumCycleDuration = 0.9
        static let cycleDurationRange = 1.5
        static let activityCyclesPerPeriod = 4.0
        // Integer multiple of the base phase so a keypress cycle closes exactly
        // once per animation period, keeping the loop seamless.
        static let pawTapCyclesPerPeriod = 8.0
        static let tapDepth = 1.4
        static let sleepPeriod = 14.0
        static let staticPeriod = 1.0
        static let fullTurn = Double.pi * 2
        static let neutralBrokenRed: UInt8 = 128
        static let neutralBrokenGreen: UInt8 = 124
        static let neutralBrokenBlue: UInt8 = 130
    }

    public static func period(behavior: PetBehaviorState) -> TimeInterval {
        switch behavior {
        case let .jumping(frameInterval):
            let interval = frameInterval.isFinite
                ? clamp(frameInterval,
                        minimum: Constants.minimumFrameInterval,
                        maximum: Constants.maximumFrameInterval)
                : Constants.maximumFrameInterval
            let normalized = (interval - Constants.minimumFrameInterval)
                / (Constants.maximumFrameInterval - Constants.minimumFrameInterval)
            let cycleDuration = Constants.minimumCycleDuration
                + normalized * Constants.cycleDurationRange
            return cycleDuration * Constants.activityCyclesPerPeriod
        case .sleeping:
            return Constants.sleepPeriod
        case .broken:
            return Constants.staticPeriod
        }
    }

    public static func sample(
        stage: Int,
        behavior: PetBehaviorState,
        overlay: PetOverlay,
        elapsed: TimeInterval,
        accent: PetColor,
        reduceMotion: Bool
    ) -> CatAnimationSample {
        let clampedStage = clamp(stage, minimum: 0, maximum: Constants.stageCount - 1)
        let pose = resolvedPose(behavior: behavior, overlay: overlay)
        let supportsMotion = pose != .broken && pose != .dragging && !reduceMotion
        let phase = supportsMotion
            ? normalizedPhase(elapsed: elapsed, period: period(behavior: behavior))
            : 0

        // Secondary, always-on micro motion that keeps the cat feeling alive.
        var bodyBreath = 0.008 * sin(phase - Double.pi / 2)
        var headOffsetX = 0.22 * sin(phase * 2 + 0.7)
        var headOffsetY = 0.12 * sin(phase * 4)
        var eyeOffsetX = 0.30 * sin(phase * 2 + 0.4)
        var eyeOffsetY = 0.10 * sin(phase + 2.1)
        var earOffset = 0.28 * sin(phase * 3 + 1.1)
        var tailOffset = 1.2 * sin(phase * 2 - 0.4)
        var blinkAmount = blink(phase: phase)

        // Primary "typing" motion: the two front paws alternate onto the keys.
        let tap = sin(phase * Constants.pawTapCyclesPerPeriod)
        let leftPress = max(0, tap)
        let rightPress = max(0, -tap)
        var leftPawOffsetX = 0.2 * leftPress
        var leftPawOffsetY = Constants.tapDepth * leftPress
        var rightPawOffsetX = -0.2 * rightPress
        var rightPawOffsetY = Constants.tapDepth * rightPress
        var screenGlow = 0.72 + 0.18 * sin(phase * 2)

        switch pose {
        case .active:
            break
        case .hovering:
            headOffsetX *= 0.4
            headOffsetY += 0.6
            eyeOffsetX *= 0.5
            eyeOffsetY += 0.15
            earOffset += 0.5
            tailOffset += 0.4
            // The cat notices the pointer and lifts its paws off the keys.
            leftPawOffsetX = 0
            leftPawOffsetY = -0.25
            rightPawOffsetX = 0
            rightPawOffsetY = -0.25
            screenGlow = 0.85
        case .startled:
            headOffsetX = 0
            headOffsetY = 0.9
            eyeOffsetX = 0
            eyeOffsetY = 0.3
            earOffset = -0.7
            blinkAmount = 0
            leftPawOffsetX = -0.3
            leftPawOffsetY = -1.6
            rightPawOffsetX = 0.3
            rightPawOffsetY = -1.6
            screenGlow = 1.0
        case .dragging:
            bodyBreath = 0
            headOffsetX = 0
            headOffsetY = -0.2
            eyeOffsetX = 0
            eyeOffsetY = -0.1
            earOffset = -0.2
            tailOffset = -0.8
            leftPawOffsetX = -0.4
            leftPawOffsetY = -0.6
            rightPawOffsetX = 0.4
            rightPawOffsetY = -0.6
            blinkAmount = 0
            screenGlow = 0.5
        case .sleeping:
            bodyBreath = supportsMotion ? 0.008 * sin(phase) : 0
            headOffsetX = -0.4
            headOffsetY = -1.0
            eyeOffsetX = 0
            eyeOffsetY = 0
            earOffset = 0.1
            tailOffset = supportsMotion ? 0.35 * sin(phase) : 0
            leftPawOffsetX = -0.2
            leftPawOffsetY = 0.3
            rightPawOffsetX = 0.2
            rightPawOffsetY = 0.3
            blinkAmount = 1
            screenGlow = 0.12
        case .broken:
            bodyBreath = 0
            headOffsetX = 0.5
            headOffsetY = -0.6
            eyeOffsetX = -0.2
            eyeOffsetY = 0.2
            earOffset = 0.5
            tailOffset = -1.2
            leftPawOffsetX = -0.5
            leftPawOffsetY = 0.4
            rightPawOffsetX = 0.6
            rightPawOffsetY = 0.2
            blinkAmount = 0.6
            screenGlow = 0
        }

        return CatAnimationSample(
            clampedStage: clampedStage,
            pose: pose,
            bodyScale: Constants.minimumBodyScale
                + Double(clampedStage) * Constants.bodyScaleStep,
            bodyRoundness: Double(clampedStage) * Constants.bodyRoundnessStep,
            bodyBreath: bodyBreath,
            headOffsetX: headOffsetX,
            headOffsetY: headOffsetY,
            eyeOffsetX: eyeOffsetX,
            eyeOffsetY: eyeOffsetY,
            earOffset: earOffset,
            tailOffset: tailOffset,
            leftPawOffsetX: leftPawOffsetX,
            leftPawOffsetY: leftPawOffsetY,
            rightPawOffsetX: rightPawOffsetX,
            rightPawOffsetY: rightPawOffsetY,
            blinkAmount: blinkAmount,
            screenGlow: clamp(screenGlow, minimum: 0, maximum: 1),
            accent: pose == .broken ? neutralAccent(alpha: accent.a) : accent,
            desaturation: pose == .broken ? 1 : 0,
            decorativeMotionEnabled: supportsMotion
        )
    }

    // Precedence mirrors the pixel path (PetAnimator.framePlan): only broken
    // outranks the pointer. A sleeping cat still perks up under the pointer and
    // takes the drag pose while being carried — sleep is an idle state, not an
    // interaction block; it shows through only once the pointer is idle.
    private static func resolvedPose(
        behavior: PetBehaviorState,
        overlay: PetOverlay
    ) -> CatPose {
        switch behavior {
        case .broken:
            return .broken
        case .sleeping:
            return pointerPose(overlay: overlay) ?? .sleeping
        case .jumping:
            return pointerPose(overlay: overlay) ?? .active
        }
    }

    // The pose a live pointer overlay imposes; nil when the pointer is idle and
    // the usage-derived behavior should show through instead.
    private static func pointerPose(overlay: PetOverlay) -> CatPose? {
        switch overlay {
        case .none:
            return nil
        case .hovering:
            return .hovering
        case .startled:
            return .startled
        case .dragging:
            return .dragging
        }
    }

    private static func normalizedPhase(
        elapsed: TimeInterval,
        period: TimeInterval
    ) -> Double {
        guard elapsed.isFinite, period > 0 else { return 0 }
        let wrapped = elapsed.truncatingRemainder(dividingBy: period)
        let normalizedElapsed = wrapped >= 0 ? wrapped : wrapped + period
        return normalizedElapsed / period * Constants.fullTurn
    }

    private static func blink(phase: Double) -> Double {
        let pulse = (cos(phase * 3 - 0.8) - 0.94) / 0.06
        let clampedPulse = clamp(pulse, minimum: 0, maximum: 1)
        return clampedPulse * clampedPulse
    }

    private static func neutralAccent(alpha: UInt8) -> PetColor {
        PetColor(
            r: Constants.neutralBrokenRed,
            g: Constants.neutralBrokenGreen,
            b: Constants.neutralBrokenBlue,
            a: alpha
        )
    }

    private static func clamp<T: Comparable>(
        _ value: T,
        minimum: T,
        maximum: T
    ) -> T {
        min(maximum, max(minimum, value))
    }
}
