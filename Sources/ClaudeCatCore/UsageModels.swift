import Foundation

public struct TokenCounts: Equatable, Codable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheCreation: Int

    public static let zero = TokenCounts(input: 0, output: 0, cacheRead: 0, cacheCreation: 0)

    public init(input: Int, output: Int, cacheRead: Int, cacheCreation: Int) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        TokenCounts(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheCreation: lhs.cacheCreation + rhs.cacheCreation
        )
    }

    // Weighted sum approximating the "cost" of the tokens, so cheap cache
    // reads do not inflate the cat's growth as much as expensive output tokens.
    public func effectiveTokens(weights: TokenWeights) -> Double {
        Double(input) * weights.input
            + Double(output) * weights.output
            + Double(cacheRead) * weights.cacheRead
            + Double(cacheCreation) * weights.cacheCreation
    }
}

public struct TokenWeights {
    public var input: Double
    public var output: Double
    public var cacheRead: Double
    public var cacheCreation: Double

    public init(
        input: Double = 1,
        output: Double = 5,
        cacheRead: Double = 0.1,
        cacheCreation: Double = 1.25
    ) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheCreation = cacheCreation
    }
}

public enum ModelFamily: String, CaseIterable, Codable {
    case opus
    case sonnet
    case haiku
    case fable
    case other

    // Case-insensitive substring match against known family names;
    // nil or unrecognized model names map to .other.
    public init(modelName: String?) {
        guard let modelName else {
            self = .other
            return
        }
        let lowered = modelName.lowercased()
        let matched = ModelFamily.allCases.first { family in
            family != .other && lowered.contains(family.rawValue)
        }
        self = matched ?? .other
    }
}

public struct UsageEvent: Equatable {
    public let timestamp: Date
    // "messageId:requestId" when both exist, bare messageId otherwise, nil when neither.
    public let dedupKey: String?
    public let modelName: String?
    public let counts: TokenCounts

    public init(timestamp: Date, dedupKey: String?, modelName: String?, counts: TokenCounts) {
        self.timestamp = timestamp
        self.dedupKey = dedupKey
        self.modelName = modelName
        self.counts = counts
    }
}

public struct DailyUsageSnapshot: Codable {
    public let dayStart: Date
    public let counts: TokenCounts
    public let perModel: [String: TokenCounts]
    public let effectiveTotal: Double
    public let stage: Int
    public let stageCount: Int
    public let tokensPerMinute: Double
    public let isIdle: Bool
    public let parseErrorCount: Int
    // Assistant records with no usable usage — a silent format-drift tripwire.
    public let suspiciousSkipCount: Int
    public let transcriptsFolderFound: Bool
    // Family of the most recently ingested event; nil when no events today.
    public let lastModelFamily: ModelFamily?

    public init(
        dayStart: Date,
        counts: TokenCounts,
        perModel: [String: TokenCounts],
        effectiveTotal: Double,
        stage: Int,
        stageCount: Int,
        tokensPerMinute: Double,
        isIdle: Bool,
        parseErrorCount: Int,
        suspiciousSkipCount: Int,
        transcriptsFolderFound: Bool,
        lastModelFamily: ModelFamily? = nil
    ) {
        self.dayStart = dayStart
        self.counts = counts
        self.perModel = perModel
        self.effectiveTotal = effectiveTotal
        self.stage = stage
        self.stageCount = stageCount
        self.tokensPerMinute = tokensPerMinute
        self.isIdle = isIdle
        self.parseErrorCount = parseErrorCount
        self.suspiciousSkipCount = suspiciousSkipCount
        self.transcriptsFolderFound = transcriptsFolderFound
        self.lastModelFamily = lastModelFamily
    }
}
