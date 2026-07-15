import Foundation

// Orchestrates the per-poll pipeline: detect logical-day rollover, scan
// candidate transcript files, incrementally read newly appended lines, parse
// them into usage events and fold them into today's accumulator, then package
// the result as a DailyUsageSnapshot.
//
// If any file reports a read-position reset (truncation or atomic replacement),
// the incremental pass is abandoned and the whole day is rebuilt from scratch
// within the same refresh: dedup keys alone cannot shield against re-reads,
// because events without a dedup key would be counted twice.
//
// Concurrency contract: TodayTracker is deliberately NOT thread-safe; the
// owner must confine it to a single serial queue. The only value that ever
// crosses threads is the returned DailyUsageSnapshot — an immutable value
// type that must remain Sendable (no classes, no reference captures).
public final class TodayTracker {
    private let config: ClaudeCatConfig
    private let fileManager: FileManager
    private let dayCalculator: LogicalDayCalculator

    private var positions: [URL: FileReadPosition] = [:]
    private var accumulator: UsageAccumulator
    private var parseErrorCount = 0
    private var suspiciousSkipCount = 0
    private var currentDayStart: Date?

    public init(config: ClaudeCatConfig, calendar: Calendar, fileManager: FileManager = .default) {
        self.config = config
        self.fileManager = fileManager
        let dayCalculator = LogicalDayCalculator(calendar: calendar, rolloverHour: config.rolloverHour)
        self.dayCalculator = dayCalculator
        self.accumulator = UsageAccumulator(dayCalculator: dayCalculator, weights: config.weights)
    }

    public func refresh(now: Date) -> DailyUsageSnapshot {
        let dayStart = dayCalculator.dayStart(containing: now)
        if dayStart != currentDayStart {
            // New logical day: drop all state so candidate files are re-read
            // from scratch and only in-day events survive ingestion.
            accumulator.resetForNewDay()
            positions.removeAll()
            parseErrorCount = 0
            suspiciousSkipCount = 0
            currentDayStart = dayStart
        }

        if scanAndIngest(dayStart: dayStart, now: now) {
            // A truncated or replaced file forced its position back to 0, so the
            // scan above may have re-ingested events that lack a dedup key. The
            // accumulated totals are no longer trustworthy — rebuild the entire
            // day from scratch. The rebuild pass reads from fresh `.start`
            // positions, which never report didReset, so it cannot recurse.
            accumulator.resetForNewDay()
            positions.removeAll()
            parseErrorCount = 0
            suspiciousSkipCount = 0
            _ = scanAndIngest(dayStart: dayStart, now: now)
        }

        var isDirectory: ObjCBool = false
        let rootFound = fileManager.fileExists(atPath: config.projectsRoot.path, isDirectory: &isDirectory)
            && isDirectory.boolValue

        let perModel = Dictionary(uniqueKeysWithValues: accumulator.perModel.map {
            ($0.key.rawValue, $0.value)
        })
        return DailyUsageSnapshot(
            dayStart: dayStart,
            counts: accumulator.totals,
            perModel: perModel,
            effectiveTotal: accumulator.effectiveTotal,
            stage: StageEngine.stage(effective: accumulator.effectiveTotal,
                                     thresholds: config.stageThresholds),
            stageCount: config.stageThresholds.count + 1,
            tokensPerMinute: StageEngine.tokensPerMinute(
                recent: accumulator.recentEffective(window: config.rateWindowSeconds, now: now),
                now: now,
                window: config.rateWindowSeconds
            ),
            isIdle: StageEngine.isIdle(lastEventAt: accumulator.lastEventAt,
                                       now: now,
                                       idleAfter: config.idleAfterSeconds),
            parseErrorCount: parseErrorCount,
            suspiciousSkipCount: suspiciousSkipCount,
            transcriptsFolderFound: rootFound,
            lastModelFamily: accumulator.lastModelFamily
        )
    }

    // Runs one incremental scan over today's candidate files, ingesting new
    // lines into the accumulator. Returns true when any file's read position
    // was reset (truncation/replacement), i.e. the day's totals may now
    // contain double-counted keyless events and need a full rebuild.
    private func scanAndIngest(dayStart: Date, now: Date) -> Bool {
        var anyReset = false
        let candidates = ProjectsScanner.candidateFiles(
            under: config.projectsRoot,
            modifiedAfter: dayStart,
            fileManager: fileManager
        )
        for url in candidates {
            // Mutate a local copy so a mid-read failure (file vanished, etc.)
            // leaves the stored position untouched and the file is retried next tick.
            var position = positions[url] ?? .start
            guard let (lines, didReset) = try? IncrementalLineReader.readNewLines(at: url, from: &position) else {
                continue
            }
            positions[url] = position
            anyReset = anyReset || didReset
            for line in lines {
                switch TranscriptLineParser.parse(line: line) {
                case .event(let event):
                    accumulator.ingest(event, now: now)
                case .malformed:
                    parseErrorCount += 1
                case .assistantWithoutUsage:
                    suspiciousSkipCount += 1
                case .skippedIrrelevant:
                    break
                }
            }
        }
        return anyReset
    }
}
