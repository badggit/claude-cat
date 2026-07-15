import Foundation

// In-memory accumulator of today's deduplicated token usage. Rejects events
// that fall outside the current logical day and events whose dedupKey was
// already seen; keeps a trimmed (timestamp, effectiveTokens) history so the
// caller can compute a short-window usage rate.
public struct UsageAccumulator {
    private let dayCalculator: LogicalDayCalculator
    private let weights: TokenWeights

    private var seenDedupKeys: Set<String> = []
    private var recentEvents: [(Date, Double)] = []
    // Ingest-time retention bound for the rate history; recentEffective callers
    // must use windows no longer than this or older entries may already be trimmed.
    private let maxRetentionWindow: TimeInterval = 3600

    public private(set) var totals: TokenCounts = .zero
    public private(set) var perModel: [ModelFamily: TokenCounts] = [:]
    public private(set) var effectiveTotal: Double = 0
    public private(set) var lastEventAt: Date?
    // Family of the most recently ingested event ("last ingested wins").
    public private(set) var lastModelFamily: ModelFamily?

    public init(dayCalculator: LogicalDayCalculator, weights: TokenWeights) {
        self.dayCalculator = dayCalculator
        self.weights = weights
    }

    // Returns false when the event was ignored (duplicate or outside the current logical day).
    @discardableResult
    public mutating func ingest(_ event: UsageEvent, now: Date) -> Bool {
        guard dayCalculator.isInCurrentDay(event.timestamp, now: now) else {
            return false
        }
        if let key = event.dedupKey {
            guard seenDedupKeys.insert(key).inserted else {
                return false
            }
        }

        let effective = event.counts.effectiveTokens(weights: weights)
        totals = totals + event.counts
        effectiveTotal += effective

        let family = ModelFamily(modelName: event.modelName)
        perModel[family] = (perModel[family] ?? .zero) + event.counts
        lastModelFamily = family

        lastEventAt = event.timestamp
        recentEvents.append((event.timestamp, effective))
        trimRecentEvents(now: now)
        return true
    }

    public func recentEffective(window: TimeInterval, now: Date) -> [(Date, Double)] {
        let cutoff = now.addingTimeInterval(-window)
        return recentEvents.filter { $0.0 >= cutoff }
    }

    public mutating func resetForNewDay() {
        totals = .zero
        perModel = [:]
        effectiveTotal = 0
        lastEventAt = nil
        lastModelFamily = nil
        seenDedupKeys.removeAll()
        recentEvents.removeAll()
    }

    private mutating func trimRecentEvents(now: Date) {
        let cutoff = now.addingTimeInterval(-maxRetentionWindow)
        recentEvents.removeAll { $0.0 < cutoff }
    }
}
