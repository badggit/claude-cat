import Foundation

public struct DailyTotal: Equatable {
    public let dayStart: Date
    public let counts: TokenCounts
    public let effective: Double

    public init(dayStart: Date, counts: TokenCounts, effective: Double) {
        self.dayStart = dayStart
        self.counts = counts
        self.effective = effective
    }
}

// Aggregates historical usage into per-day totals for the `calibrate` command.
// Unlike the live tracker this is a one-shot, full (non-incremental) read.
public enum HistoryAggregator {
    public static func dailyTotals(root: URL, days: Int, now: Date,
                                   dayCalculator: LogicalDayCalculator,
                                   weights: TokenWeights,
                                   fileManager: FileManager) -> [DailyTotal] {
        // The cutoff is a flat `now - days * 86400` subtraction, intentionally
        // NOT aligned to the rollover boundary — the oldest bucket may be a
        // partial day.
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let files = ProjectsScanner.candidateFiles(under: root, modifiedAfter: cutoff,
                                                   fileManager: fileManager)
        // Dedup spans the whole run: the same API response can be replicated
        // into several transcript files (e.g. resumed sessions).
        var seenKeys = Set<String>()
        var totalsByDay: [Date: TokenCounts] = [:]

        for file in files {
            var position = FileReadPosition.start
            // First read from `.start`, so didReset is always false here.
            guard let (lines, _) = try? IncrementalLineReader.readNewLines(at: file, from: &position) else {
                continue
            }
            for line in lines {
                guard case .event(let event) = TranscriptLineParser.parse(line: line) else {
                    continue
                }
                // A fresh mtime only proves the file has recent lines; each event
                // still has to fall inside the requested window itself.
                guard event.timestamp >= cutoff else { continue }
                if let key = event.dedupKey {
                    guard seenKeys.insert(key).inserted else { continue }
                }
                let day = dayCalculator.dayStart(containing: event.timestamp)
                totalsByDay[day] = (totalsByDay[day] ?? .zero) + event.counts
            }
        }

        return totalsByDay
            .sorted { $0.key < $1.key }
            .map { day, counts in
                DailyTotal(dayStart: day, counts: counts,
                           effective: counts.effectiveTokens(weights: weights))
            }
    }
}
