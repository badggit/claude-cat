import Foundation

// Generates the launchd agent plist for the "Launch at Login" feature.
// Pure string generation — cross-platform so it stays unit-testable on Linux.
public enum LaunchAgentPlist {
    public static let label = "com.claudecat.app"

    // RunAtLoad true, KeepAlive FALSE — KeepAlive would make launchd resurrect the app
    // after Quit; login start needs RunAtLoad only.
    // Non-empty environment is embedded as EnvironmentVariables (launchd starts agents
    // with a bare env — the user's shell CLAUDE_CAT_PROJECTS_DIR would otherwise vanish).
    public static func xml(executablePath: String, environment: [String: String]) -> String {
        var dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
        ]
        if !environment.isEmpty {
            dict["EnvironmentVariables"] = environment
        }
        // PropertyListSerialization guarantees correct XML escaping of paths
        // containing spaces or entities; a fixed dictionary cannot fail to
        // serialize, so a failure here is a programmer error.
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dict,
                                                          format: .xml,
                                                          options: 0)
            return String(decoding: data, as: UTF8.self)
        } catch {
            fatalError("LaunchAgentPlist serialization failed: \(error)")
        }
    }
}
