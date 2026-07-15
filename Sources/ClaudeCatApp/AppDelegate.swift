#if os(macOS)

import AppKit
import ClaudeCatCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Retained for the app's lifetime; polling and every display layer stop
    // if the engine is released. The engine creates/destroys its own layers
    // (menu-bar item, pet) per the persisted display flags.
    private var usageEngine: UsageEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        usageEngine = UsageEngine(config: ClaudeCatConfig.standard())
    }
}

#endif
