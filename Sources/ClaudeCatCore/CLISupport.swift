import Foundation

public enum CLICommand: Equatable {
    case today(json: Bool)
    case calibrate(days: Int)
    case watch
}

public enum CLIParseError: Error, Equatable {
    case unknownCommand(String)
    case invalidValue(String)
}

// Argument parsing and output formatting for the claude-cat CLI. Lives in the
// core target (instead of the executable) so it is unit-testable and reusable
// by the menu app.
public enum CLISupport {
    public static let usageText = """
    Usage: claude-cat <command>

    Commands:
      today [--json]           Print today's usage snapshot
      calibrate [--days N]     Print per-day effective totals (default: 7 days)
      watch                    Poll and print a snapshot line forever
    """

    // Parses CLI arguments (without argv[0]) into a command.
    public static func parseArguments(_ args: [String]) -> Result<CLICommand, CLIParseError> {
        guard let command = args.first else {
            return .failure(.unknownCommand(""))
        }
        let rest = Array(args.dropFirst())
        switch command {
        case "today":
            switch rest {
            case []:
                return .success(.today(json: false))
            case ["--json"]:
                return .success(.today(json: true))
            default:
                return .failure(.invalidValue(rest.joined(separator: " ")))
            }
        case "calibrate":
            switch rest {
            case []:
                return .success(.calibrate(days: 7))
            case let flags where flags.count == 2 && flags[0] == "--days":
                let raw = flags[1]
                guard let days = Int(raw), days > 0 else {
                    return .failure(.invalidValue(raw))
                }
                return .success(.calibrate(days: days))
            default:
                return .failure(.invalidValue(rest.joined(separator: " ")))
            }
        case "watch":
            guard rest.isEmpty else {
                return .failure(.invalidValue(rest.joined(separator: " ")))
            }
            return .success(.watch)
        default:
            return .failure(.unknownCommand(command))
        }
    }

    public static func formatSnapshot(_ s: DailyUsageSnapshot) -> String {
        var lines: [String] = []
        lines.append("Effective:  \(abbreviate(s.effectiveTotal)) tokens (stage \(s.stage + 1)/\(s.stageCount))")
        lines.append("Raw:        input=\(s.counts.input) output=\(s.counts.output) "
            + "cacheRead=\(s.counts.cacheRead) cacheCreation=\(s.counts.cacheCreation)")
        for (model, counts) in s.perModel.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(model): input=\(counts.input) output=\(counts.output) "
                + "cacheRead=\(counts.cacheRead) cacheCreation=\(counts.cacheCreation)")
        }
        lines.append("Rate:       \(abbreviate(s.tokensPerMinute)) tokens/min")
        lines.append("Idle:       \(s.isIdle ? "yes" : "no")")
        if s.parseErrorCount > 0 || s.suspiciousSkipCount > 0 {
            lines.append("Diagnostics: parseErrors=\(s.parseErrorCount) "
                + "suspiciousSkips=\(s.suspiciousSkipCount)")
        }
        if !s.transcriptsFolderFound {
            lines.append("Warning:    transcripts folder not found")
        }
        return lines.joined(separator: "\n")
    }

    public static func formatSnapshotJSON(_ s: DailyUsageSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(s), as: UTF8.self)
    }

    public static func formatCalibrationTable(_ rows: [DailyTotal], calendar: Calendar) -> String {
        var lines = ["Day         Effective   Input       Output      CacheRead   CacheCreate"]
        for row in rows {
            let c = calendar.dateComponents([.year, .month, .day], from: row.dayStart)
            let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            let columns = [
                abbreviate(row.effective),
                abbreviate(Double(row.counts.input)),
                abbreviate(Double(row.counts.output)),
                abbreviate(Double(row.counts.cacheRead)),
                abbreviate(Double(row.counts.cacheCreation)),
            ].map { $0.padding(toLength: 11, withPad: " ", startingAt: 0) }
            lines.append("\(day)  \(columns.joined(separator: " "))")
        }
        return lines.joined(separator: "\n")
    }

    // Compact human-friendly magnitude: 950 -> "950", 1_834_502 -> "1.8M",
    // 2_000_000 -> "2M" (one decimal, trailing .0 dropped, no thousands separators).
    public static func abbreviate(_ value: Double) -> String {
        let units: [(threshold: Double, suffix: String)] = [
            (1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K"),
        ]
        for unit in units where value >= unit.threshold {
            var scaled = String(format: "%.1f", value / unit.threshold)
            if scaled.hasSuffix(".0") {
                scaled = String(scaled.dropLast(2))
            }
            return scaled + unit.suffix
        }
        return String(Int(value.rounded()))
    }
}
