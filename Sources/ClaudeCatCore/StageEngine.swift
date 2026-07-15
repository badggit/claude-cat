import Foundation

// Pure functions mapping usage metrics to cat presentation state:
// growth stage, activity rate, idleness and animation frame speed.
public enum StageEngine {
    // A value exactly at a threshold belongs to the higher stage,
    // so the result counts thresholds <= effective (0...thresholds.count).
    public static func stage(effective: Double, thresholds: [Double]) -> Int {
        thresholds.filter { $0 <= effective }.count
    }

    // Sums effective tokens of events inside [now - window, now]
    // and normalizes the sum to a per-minute rate.
    public static func tokensPerMinute(recent: [(Date, Double)], now: Date, window: TimeInterval) -> Double {
        guard window > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-window)
        let total = recent
            .filter { $0.0 >= cutoff && $0.0 <= now }
            .reduce(0) { $0 + $1.1 }
        return total * 60 / window
    }

    // Idle when there was no event at all, or the last event happened
    // strictly more than idleAfter seconds ago (exactly idleAfter is not idle).
    public static func isIdle(lastEventAt: Date?, now: Date, idleAfter: TimeInterval) -> Bool {
        guard let lastEventAt else { return true }
        return now.timeIntervalSince(lastEventAt) > idleAfter
    }

    // Maps token rate to an animation frame interval via an
    // inverse-proportional curve, clamped to [fastest, slowest].
    public static func frameInterval(tokensPerMinute: Double,
                                     slowest: TimeInterval, fastest: TimeInterval) -> TimeInterval {
        guard tokensPerMinute > 0, fastest > 0 else { return slowest }
        // Rate at which the curve reaches the fastest interval; below it the
        // interval scales inversely with the rate.
        let referenceRate: Double = 1000
        let raw = slowest * referenceRate / (referenceRate + tokensPerMinute * (slowest / fastest - 1))
        return min(slowest, max(fastest, raw))
    }
}
