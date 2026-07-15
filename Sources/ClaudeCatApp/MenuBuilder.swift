#if os(macOS)

import AppKit
import ClaudeCatCore
import ClaudeCatPet

// Builds the status-item dropdown menu from the latest usage snapshot.
// All informational rows are disabled; "Launch at Login" and "Quit" are the
// actionable items.
enum MenuBuilder {
    private static let updatedTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // Identifier of the live countdown row so the engine can retitle it
    // each second while the menu stays open.
    static let countdownIdentifier = NSUserInterfaceItemIdentifier("countdown")

    static func build(snapshot: DailyUsageSnapshot?,
                      updatedAt: Date? = nil,
                      secondsUntilRefresh: Int? = nil,
                      stageNames: [String] = [],
                      creatures: [(id: String, name: String)] = [],
                      activeCreatureID: String = "",
                      displayFlags: DisplayFlags = .bothOn,
                      canDisableMenuBar: Bool = true,
                      canDisablePet: Bool = true,
                      launchAtLoginEnabled: Bool = false,
                      target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let snapshot {
            appendUsageItems(snapshot: snapshot, updatedAt: updatedAt, stageNames: stageNames, to: menu)
        } else {
            menu.addItem(infoItem("Loading…"))
        }

        menu.addItem(NSMenuItem.separator())
        let countdown = infoItem(countdownTitle(seconds: secondsUntilRefresh))
        countdown.identifier = countdownIdentifier
        menu.addItem(countdown)
        let refresh = NSMenuItem(title: "Refresh Now",
                                 action: #selector(UsageEngine.refreshNow(_:)),
                                 keyEquivalent: "r")
        refresh.target = target
        menu.addItem(refresh)

        if !creatures.isEmpty {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(infoItem("Animal"))
            for creature in creatures {
                let item = NSMenuItem(title: creature.name,
                                      action: #selector(UsageEngine.selectCreature(_:)),
                                      keyEquivalent: "")
                item.target = target
                item.representedObject = creature.id
                item.state = creature.id == activeCreatureID ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(infoItem("Display"))
        // The last enabled display stays checked but grayed out — the policy
        // guarantees at least one display is always on.
        let menuBarToggle = NSMenuItem(title: "Show in Menu Bar",
                                       action: #selector(UsageEngine.toggleMenuBarDisplay(_:)),
                                       keyEquivalent: "")
        menuBarToggle.target = target
        menuBarToggle.state = displayFlags.menuBar ? .on : .off
        menuBarToggle.isEnabled = canDisableMenuBar
        menu.addItem(menuBarToggle)
        let petToggle = NSMenuItem(title: "Show on Screen",
                                   action: #selector(UsageEngine.togglePetDisplay(_:)),
                                   keyEquivalent: "")
        petToggle.target = target
        petToggle.state = displayFlags.pet ? .on : .off
        petToggle.isEnabled = canDisablePet
        menu.addItem(petToggle)

        menu.addItem(NSMenuItem.separator())
        let launchAtLogin = NSMenuItem(
            title: "Launch at Login",
            action: #selector(UsageEngine.toggleLaunchAtLogin(_:)),
            keyEquivalent: "")
        launchAtLogin.target = target
        launchAtLogin.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLogin)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    private static func appendUsageItems(snapshot: DailyUsageSnapshot,
                                         updatedAt: Date?,
                                         stageNames: [String],
                                         to menu: NSMenu) {
        let stageSuffix = stageNames.isEmpty
            ? ""
            : " (\(stageNames[min(max(snapshot.stage, 0), stageNames.count - 1)]))"
        menu.addItem(infoItem(
            "Today: \(CLISupport.abbreviate(snapshot.effectiveTotal)) eff. tokens\(stageSuffix)"
        ))
        menu.addItem(infoItem("Input: \(abbreviate(snapshot.counts.input))"))
        menu.addItem(infoItem("Output: \(abbreviate(snapshot.counts.output))"))
        menu.addItem(infoItem("Cache read: \(abbreviate(snapshot.counts.cacheRead))"))
        menu.addItem(infoItem("Cache create: \(abbreviate(snapshot.counts.cacheCreation))"))

        appendModelsSection(perModel: snapshot.perModel, to: menu)

        menu.addItem(infoItem("Rate: \(CLISupport.abbreviate(snapshot.tokensPerMinute))/min"))
        if let family = snapshot.lastModelFamily {
            menu.addItem(infoItem("Model: \(family.rawValue.capitalized)"))
        }
        if let updatedAt {
            menu.addItem(infoItem("Updated \(updatedTimeFormatter.string(from: updatedAt))"))
        }

        for line in diagnosticsLines(snapshot: snapshot) {
            menu.addItem(infoItem(line))
        }
    }

    private static func appendModelsSection(perModel: [String: TokenCounts], to menu: NSMenu) {
        // Families with all-zero counts carry no information; hide them.
        let families = perModel
            .filter { $0.value != .zero }
            .sorted { $0.key < $1.key }
        guard !families.isEmpty else { return }

        menu.addItem(infoItem("Models"))
        for (family, counts) in families {
            let total = counts.input + counts.output + counts.cacheRead + counts.cacheCreation
            menu.addItem(infoItem("  \(family.capitalized): \(abbreviate(total))"))
        }
    }

    private static func diagnosticsLines(snapshot: DailyUsageSnapshot) -> [String] {
        var lines: [String] = []
        if !snapshot.transcriptsFolderFound {
            lines.append("⚠ Transcripts folder not found")
        }
        if snapshot.parseErrorCount > 0 || snapshot.suspiciousSkipCount > 0 {
            lines.append("⚠ \(snapshot.parseErrorCount) lines unrecognized, "
                + "\(snapshot.suspiciousSkipCount) suspicious skips")
        }
        return lines
    }

    static func countdownTitle(seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "Refreshing…" }
        return "Next refresh in \(seconds)s"
    }

    private static func abbreviate(_ value: Int) -> String {
        CLISupport.abbreviate(Double(value))
    }

    // Informational rows have no action and stay visually disabled.
    private static func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

#endif
