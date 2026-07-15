import Foundation
import ClaudeCatCore

// Base animation the pet plays, derived purely from the usage snapshot.
public enum PetBehaviorState: Equatable {
    case jumping(frameInterval: TimeInterval)
    case sleeping
    case broken
}

// Short-lived interaction state layered on top of the base behavior.
public enum PetOverlay: Equatable {
    case none
    case hovering
    case startled
    case dragging
}

// Pure state-selection rules mapping usage snapshots and interaction
// inputs to pet presentation. Mirrors the menu-bar precedence in
// StatusItemController.apply(snapshot:); rendering lives in the app layer.
public enum PetStateEngine {
    // Sleeping pets animate slowly to stay within the energy budget.
    public static let sleepFrameInterval: TimeInterval = 1.5

    // How long a sleeping pet stays awake after being poked.
    public static let startleDuration: TimeInterval = 2.0

    // Precedence: broken (diagnostics failure) > sleeping (idle) > jumping.
    public static func baseState(snapshot: DailyUsageSnapshot,
                                 suspiciousSkipThreshold: Int,
                                 slowestInterval: TimeInterval,
                                 fastestInterval: TimeInterval) -> PetBehaviorState {
        let looksBroken = !snapshot.transcriptsFolderFound
            || snapshot.suspiciousSkipCount > suspiciousSkipThreshold
        if looksBroken {
            return .broken
        }
        if snapshot.isIdle {
            return .sleeping
        }
        let interval = StageEngine.frameInterval(tokensPerMinute: snapshot.tokensPerMinute,
                                                 slowest: slowestInterval,
                                                 fastest: fastestInterval)
        return .jumping(frameInterval: interval)
    }

    // Precedence: dragging > startled (while now < startledUntil) > hovering > none.
    public static func effectiveOverlay(dragging: Bool,
                                        startledUntil: Date?,
                                        hovering: Bool,
                                        now: Date) -> PetOverlay {
        if dragging {
            return .dragging
        }
        if let startledUntil, now < startledUntil {
            return .startled
        }
        if hovering {
            return .hovering
        }
        return .none
    }

    // Keeps a persisted or computed stage inside the valid sprite range.
    // A non-positive stageCount has no valid range; 0 is the least-wrong
    // answer and callers always pass the fixed catalog stage count.
    public static func clampedStage(_ stage: Int, stageCount: Int) -> Int {
        guard stageCount > 0 else { return 0 }
        return max(0, min(stage, stageCount - 1))
    }
}
