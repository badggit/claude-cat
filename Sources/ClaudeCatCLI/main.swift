import Foundation
import ClaudeCatCore

func writeLine(_ text: String, to handle: FileHandle) {
    handle.write(Data((text + "\n").utf8))
}

// Compact one-line snapshot used by `watch`, one line per poll tick.
func watchLine(for snapshot: DailyUsageSnapshot) -> String {
    var line = "effective=\(CLISupport.abbreviate(snapshot.effectiveTotal)) "
        + "stage=\(snapshot.stage + 1)/\(snapshot.stageCount) "
        + "rate=\(CLISupport.abbreviate(snapshot.tokensPerMinute))/min "
        + "idle=\(snapshot.isIdle ? "yes" : "no")"
    if snapshot.parseErrorCount > 0 || snapshot.suspiciousSkipCount > 0 {
        line += " parseErrors=\(snapshot.parseErrorCount)"
            + " suspiciousSkips=\(snapshot.suspiciousSkipCount)"
    }
    return line
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch CLISupport.parseArguments(arguments) {
case .failure:
    writeLine(CLISupport.usageText, to: .standardError)
    exit(2)
case .success(let command):
    let config = ClaudeCatConfig.standard(environment: ProcessInfo.processInfo.environment)
    // The CLI is the one place where the machine's current time zone is correct.
    let calendar = Calendar.current

    switch command {
    case .today(let json):
        let tracker = TodayTracker(config: config, calendar: calendar)
        let snapshot = tracker.refresh(now: Date())
        if json {
            do {
                writeLine(try CLISupport.formatSnapshotJSON(snapshot), to: .standardOutput)
            } catch {
                writeLine("Failed to encode snapshot as JSON: \(error)", to: .standardError)
                exit(1)
            }
        } else {
            writeLine(CLISupport.formatSnapshot(snapshot), to: .standardOutput)
        }
    case .calibrate(let days):
        let dayCalculator = LogicalDayCalculator(calendar: calendar,
                                                 rolloverHour: config.rolloverHour)
        let rows = HistoryAggregator.dailyTotals(
            root: config.projectsRoot,
            days: days,
            now: Date(),
            dayCalculator: dayCalculator,
            weights: config.weights,
            fileManager: .default
        )
        writeLine(CLISupport.formatCalibrationTable(rows, calendar: calendar), to: .standardOutput)
    case .watch:
        let tracker = TodayTracker(config: config, calendar: calendar)
        while true {
            writeLine(watchLine(for: tracker.refresh(now: Date())), to: .standardOutput)
            Thread.sleep(forTimeInterval: config.pollIntervalSeconds)
        }
    }
}
