import Foundation

public enum ParseOutcome: Equatable {
    case event(UsageEvent)
    case skippedIrrelevant
    case assistantWithoutUsage
    case malformed
}

// Fully-optional Codable mirror of a transcript jsonl record. Every field is
// optional so schema drift degrades to .assistantWithoutUsage/.malformed
// instead of hard decode failures; unknown keys are ignored by Codable.
private struct TranscriptRecord: Decodable {
    struct Message: Decodable {
        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheReadInputTokens: Int?
            let cacheCreationInputTokens: Int?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
                case cacheCreationInputTokens = "cache_creation_input_tokens"
            }
        }

        let id: String?
        let model: String?
        let usage: Usage?
    }

    let type: String?
    let timestamp: String?
    let requestId: String?
    let message: Message?
}

public enum TranscriptLineParser {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // Hot path: parse() runs for every new transcript line, so the decoder
    // is shared instead of being allocated per call.
    private static let decoder = JSONDecoder()

    public static func parse(line: String) -> ParseOutcome {
        // Fast substring prefilter: usage-bearing assistant lines always
        // contain both markers, so anything else skips JSON decoding entirely.
        guard line.contains("assistant"), line.contains("usage") else {
            return .skippedIrrelevant
        }
        guard let data = line.data(using: .utf8),
              let record = try? decoder.decode(TranscriptRecord.self, from: data) else {
            return .malformed
        }
        guard record.type == "assistant" else {
            return .skippedIrrelevant
        }
        guard let usage = record.message?.usage else {
            return .assistantWithoutUsage
        }
        guard let rawTimestamp = record.timestamp,
              let timestamp = parseTimestamp(rawTimestamp) else {
            return .malformed
        }
        let counts = TokenCounts(
            input: usage.inputTokens ?? 0,
            output: usage.outputTokens ?? 0,
            cacheRead: usage.cacheReadInputTokens ?? 0,
            cacheCreation: usage.cacheCreationInputTokens ?? 0
        )
        return .event(UsageEvent(
            timestamp: timestamp,
            dedupKey: dedupKey(messageId: record.message?.id, requestId: record.requestId),
            modelName: record.message?.model,
            counts: counts
        ))
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        fractionalFormatter.date(from: raw) ?? plainFormatter.date(from: raw)
    }

    private static func dedupKey(messageId: String?, requestId: String?) -> String? {
        guard let messageId else { return nil }
        guard let requestId else { return messageId }
        return "\(messageId):\(requestId)"
    }
}
