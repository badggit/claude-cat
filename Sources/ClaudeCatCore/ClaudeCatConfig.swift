import Foundation

public struct ClaudeCatConfig {
    // Local hour at which the "usage day" rolls over (5 = 5 AM), so late-night
    // sessions count toward the previous day.
    public var rolloverHour: Int
    // Gap the app layer waits AFTER a refresh finishes before starting the
    // next one, so the effective cadence is (refresh duration + this value).
    public var pollIntervalSeconds: Double
    public var rateWindowSeconds: Double
    public var idleAfterSeconds: Double
    public var weights: TokenWeights
    // Five ascending effective-token thresholds splitting growth into six stages.
    // Calibrated against a real week of usage (daily effective totals 0.6M-30.5M),
    // so a light day stays in the low stages and only a very heavy day maxes out.
    public var stageThresholds: [Double]
    // Per-day count of assistant records with no usable usage above which the
    // cat shows a "confused" state (likely transcript format drift).
    public var suspiciousSkipThreshold: Int
    public var projectsRoot: URL

    public init(
        rolloverHour: Int,
        pollIntervalSeconds: Double,
        rateWindowSeconds: Double,
        idleAfterSeconds: Double,
        weights: TokenWeights,
        stageThresholds: [Double],
        suspiciousSkipThreshold: Int,
        projectsRoot: URL
    ) {
        self.rolloverHour = rolloverHour
        self.pollIntervalSeconds = pollIntervalSeconds
        self.rateWindowSeconds = rateWindowSeconds
        self.idleAfterSeconds = idleAfterSeconds
        self.weights = weights
        self.stageThresholds = stageThresholds
        self.suspiciousSkipThreshold = suspiciousSkipThreshold
        self.projectsRoot = projectsRoot
    }

    // Default configuration; CLAUDE_CAT_PROJECTS_DIR in the given environment
    // overrides the transcripts folder (~/.claude/projects by default).
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> ClaudeCatConfig {
        let projectsRoot: URL
        if let override = environment["CLAUDE_CAT_PROJECTS_DIR"], !override.isEmpty {
            projectsRoot = URL(fileURLWithPath: override)
        } else {
            projectsRoot = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude")
                .appendingPathComponent("projects")
        }
        return ClaudeCatConfig(
            rolloverHour: 5,
            pollIntervalSeconds: 5,
            rateWindowSeconds: 300,
            idleAfterSeconds: 30,
            weights: TokenWeights(),
            stageThresholds: [1_000_000, 3_000_000, 8_000_000, 16_000_000, 28_000_000],
            suspiciousSkipThreshold: 10,
            projectsRoot: projectsRoot
        )
    }
}
