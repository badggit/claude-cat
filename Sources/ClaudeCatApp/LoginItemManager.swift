#if os(macOS)

import AppKit
import ClaudeCatCore

// Manages the "Launch at Login" launchd agent: writes/removes the plist in
// ~/Library/LaunchAgents and bootstraps/boots-out the agent via launchctl.
// This is the project's sole intentional disk write.
final class LoginItemManager {
    private let fileManager = FileManager.default

    private var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(LaunchAgentPlist.label).plist")
    }

    // The plist file on disk is the source of truth for the menu checkbox;
    // launchctl state is best-effort only.
    var isEnabled: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }

    func enable() {
        let executablePath = URL(fileURLWithPath: CommandLine.arguments[0])
            .standardizedFileURL.path
        // A binary inside .build/ is wiped by the next clean/rebuild, which
        // would strand launchd on a dead path — refuse and point at the docs.
        if executablePath.contains("/.build/") {
            showBuildPathAlert()
            return
        }

        var environment: [String: String] = [:]
        if let projectsDir = ProcessInfo.processInfo.environment["CLAUDE_CAT_PROJECTS_DIR"] {
            environment["CLAUDE_CAT_PROJECTS_DIR"] = projectsDir
        }

        let xml = LaunchAgentPlist.xml(executablePath: executablePath,
                                       environment: environment)
        do {
            try fileManager.createDirectory(at: launchAgentsDirectory,
                                            withIntermediateDirectories: true)
            try xml.write(to: plistURL, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(
                Data("claude-cat: failed to write launch agent plist: \(error)\n".utf8))
            return
        }
        runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    func disable() {
        runLaunchctl(["bootout", "gui/\(getuid())/\(LaunchAgentPlist.label)"])
        do {
            try fileManager.removeItem(at: plistURL)
        } catch {
            FileHandle.standardError.write(
                Data("claude-cat: failed to remove launch agent plist: \(error)\n".utf8))
        }
    }

    private func showBuildPathAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Launch at Login unavailable from a build directory"
        alert.informativeText = "Running from a build directory — copy the binary to "
            + "~/bin first (see README.md), then enable Launch at Login."
        alert.runModal()
    }

    // Non-zero launchctl exits are swallowed on purpose (logged to stderr):
    // the plist file, not launchd state, drives the checkbox.
    private func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let message = "claude-cat: launchctl \(arguments.joined(separator: " ")) "
                    + "exited with status \(process.terminationStatus)\n"
                FileHandle.standardError.write(Data(message.utf8))
            }
        } catch {
            FileHandle.standardError.write(
                Data("claude-cat: failed to run launchctl: \(error)\n".utf8))
        }
    }
}

#endif
