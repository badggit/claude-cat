#if os(macOS)
import AppKit

let app = NSApplication.shared
// Accessory policy: menu-bar only, no Dock icon. Required because this is a
// bare SwiftPM binary with no app bundle / Info.plist (LSUIElement).
app.setActivationPolicy(.accessory)

if CommandLine.arguments.contains("--pet-spike") {
    // Phase-0 spike replaces the normal app: only the overlay panel used to
    // validate the desktop-pet window premises, no tracker or menu bar item.
    // app.run() never returns, so this local keeps the controller alive.
    let spike = PetSpikeController()
    spike.show()
    app.run()
} else {
    // NSApplication.delegate is weak — keep a strong reference for the app's lifetime.
    let delegate = AppDelegate()
    app.delegate = delegate

    app.run()
}
#else
import Foundation

// Stub so the package builds on Linux; the app itself is macOS-only.
print("claude-cat-app is macOS-only")
exit(1)
#endif
