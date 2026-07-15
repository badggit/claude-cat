#if os(macOS)

import AppKit
import ClaudeCatCore
import ClaudeCatPet

// A display surface driven by the usage engine. The engine resolves the
// accent color and the active creature so every attached layer renders the
// same state; apply is always called on the main thread.
protocol UsageDisplayLayer: AnyObject {
    func apply(snapshot: DailyUsageSnapshot, accent: NSColor?, creature: RenderedCreature)
}

// Visibility hooks for the desktop-pet layer: the engine calls show() right
// after creating it and hide() right before releasing it, so the pet window
// can order itself in/out without the engine knowing about NSWindow.
protocol PetLayerLifecycle: AnyObject {
    func show()
    func hide()
}

// Owns the usage tracker, poll timer, shared status menu, creature selection
// and login-item state, and fans immutable snapshots out to attached display
// layers (the menu-bar item today, the desktop pet later). There is exactly
// one tracker refresh per poll interval regardless of how many layers are
// attached.
//
// Concurrency contract: the TodayTracker is NOT thread-safe, so it is
// confined to one private serial queue — every refresh runs there. The
// resulting immutable DailyUsageSnapshot is handed back to the main thread,
// and `lastSnapshot` (plus all UI/timer state) is read and written on the
// main thread ONLY.
final class UsageEngine: NSObject, NSMenuDelegate {
    // Weak box so the engine never retains a layer; released layers drop out
    // on the next prune.
    private struct WeakLayer {
        weak var layer: UsageDisplayLayer?
    }

    private let config: ClaudeCatConfig
    private let tracker: TodayTracker
    private let trackerQueue = DispatchQueue(label: "claude-cat.today-tracker")
    // Persistent menu shared by every display layer; its items are rebuilt
    // lazily in menuNeedsUpdate(_:) each time the user opens it.
    private let statusMenu = NSMenu()
    private let loginItemManager = LoginItemManager()

    // Main-thread-only state.
    private var layers: [WeakLayer] = []
    private var lastSnapshot: DailyUsageSnapshot?
    // Wall-clock moment the last snapshot arrived, shown as "Updated" in the menu.
    private var lastSnapshotDate: Date?
    private var pollTimer: Timer?
    // Ticks once a second while the menu is open to keep the countdown live.
    private var menuTickTimer: Timer?
    private weak var countdownItem: NSMenuItem?
    // Currently selected creature, persisted across launches.
    private var creature: RenderedCreature
    private static let creatureDefaultsKey = "selectedCreatureID"
    static let displayMenuBarEnabledKey = "displayMenuBarEnabled"
    static let displayPetEnabledKey = "displayPetEnabled"

    // Which displays are enabled; always kept legal by DisplayTogglePolicy
    // (at least one display stays on).
    private var displayFlags: DisplayFlags
    // Owned display layers; created when the matching flag turns on and
    // released when it turns off. Layer churn never touches the tracker or
    // the poll timer.
    private var statusItemController: StatusItemController?
    private var petLayer: (UsageDisplayLayer & PetLayerLifecycle)?
    // Registered in init via registerPetLayerFactory(); setting the factory
    // applies the current flag at once. A nil factory (tests, early init)
    // means the pet flag persists without a visible layer.
    var petLayerFactory: (() -> UsageDisplayLayer & PetLayerLifecycle)? {
        didSet { syncPetLayer() }
    }

    // Shared dropdown, also used as the pet's right-click popup later.
    var menu: NSMenu { statusMenu }
    var currentCreature: RenderedCreature { creature }

    init(config: ClaudeCatConfig = .standard()) {
        self.config = config
        self.tracker = TodayTracker(config: config, calendar: Calendar.current)
        let savedID = UserDefaults.standard.string(forKey: Self.creatureDefaultsKey)
            ?? CreatureCatalog.defaultID
        self.creature = CreatureCatalog.creature(id: savedID)
        let storedFlags = Self.loadDisplayFlags()
        self.displayFlags = DisplayTogglePolicy.sanitized(storedFlags)
        super.init()

        // Repair persisted both-off corruption immediately so the next launch
        // reads legal flags even if this run never toggles anything.
        if displayFlags != storedFlags {
            persistDisplayFlags()
        }
        statusMenu.delegate = self
        syncMenuBarLayer()
        registerPetLayerFactory()

        // The first refresh schedules the next one from its own completion, so
        // polling is self-driving from here on (see scheduleNextPoll).
        requestRefresh()
    }

    deinit {
        pollTimer?.invalidate()
        menuTickTimer?.invalidate()
    }

    // MARK: - Display layers

    // Replays the latest snapshot immediately so a freshly attached layer
    // renders without waiting for the next poll.
    func attach(_ layer: UsageDisplayLayer) {
        prune()
        guard !layers.contains(where: { $0.layer === layer }) else { return }
        layers.append(WeakLayer(layer: layer))
        if let snapshot = lastSnapshot {
            layer.apply(snapshot: snapshot, accent: accent(for: snapshot), creature: creature)
        }
    }

    // Detaching only forgets the layer; the tracker, poll timer and menu keep
    // running for the remaining layers.
    func detach(_ layer: UsageDisplayLayer) {
        layers.removeAll { $0.layer === layer || $0.layer == nil }
    }

    private func prune() {
        layers.removeAll { $0.layer == nil }
    }

    // MARK: - Polling

    // Dispatches one tracker refresh onto the serial queue and applies the
    // snapshot back on the main thread.
    private func requestRefresh() {
        trackerQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.tracker.refresh(now: Date())
            DispatchQueue.main.async {
                self.apply(snapshot: snapshot)
            }
        }
    }

    private func apply(snapshot: DailyUsageSnapshot) {
        lastSnapshot = snapshot
        lastSnapshotDate = Date()
        fanOut(snapshot: snapshot)
        // Re-arm from the completion of the refresh that just finished, so the
        // gap between polls is (refresh duration + pollIntervalSeconds) rather
        // than a fixed period. A manual refresh also lands here and resets the
        // countdown, which is the intended behavior.
        scheduleNextPoll()
    }

    // Schedules a single one-shot poll pollIntervalSeconds from now, replacing
    // any pending timer so exactly one refresh is ever queued.
    private func scheduleNextPoll() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: config.pollIntervalSeconds,
                                         repeats: false) { [weak self] _ in
            self?.requestRefresh()
        }
    }

    private func fanOut(snapshot: DailyUsageSnapshot) {
        prune()
        let accent = accent(for: snapshot)
        for box in layers {
            box.layer?.apply(snapshot: snapshot, accent: accent, creature: creature)
        }
    }

    // Active model color; nil keeps the creature as an adaptive template image.
    private func accent(for snapshot: DailyUsageSnapshot) -> NSColor? {
        snapshot.lastModelFamily.flatMap { Self.accentColors[$0] }
    }

    // MARK: - Menu

    // Rebuilds the menu contents from the latest snapshot right before AppKit
    // shows it; NSMenuItems can belong to only one menu, so each built item is
    // detached from the throwaway menu before moving into the persistent one.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let built = MenuBuilder.build(snapshot: lastSnapshot,
                                      updatedAt: lastSnapshotDate,
                                      secondsUntilRefresh: secondsUntilRefresh(),
                                      stageNames: creature.stageNames,
                                      creatures: CreatureCatalog.all.map { ($0.id, $0.displayName) },
                                      activeCreatureID: creature.id,
                                      displayFlags: displayFlags,
                                      canDisableMenuBar: canDisableMenuBarDisplay,
                                      canDisablePet: DisplayTogglePolicy.canDisable(displayFlags, .pet),
                                      launchAtLoginEnabled: loginItemManager.isEnabled,
                                      target: self)
        menu.removeAllItems()
        menu.autoenablesItems = false
        for item in built.items {
            built.removeItem(item)
            menu.addItem(item)
        }
        countdownItem = menu.items.first { $0.identifier == MenuBuilder.countdownIdentifier }
    }

    // The countdown timer must run in .common modes; a default-mode timer is
    // starved while the menu tracking run loop is active.
    func menuWillOpen(_ menu: NSMenu) {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateCountdownItem()
        }
        RunLoop.current.add(timer, forMode: .common)
        menuTickTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        menuTickTimer?.invalidate()
        menuTickTimer = nil
        countdownItem = nil
    }

    private func updateCountdownItem() {
        countdownItem?.title = MenuBuilder.countdownTitle(seconds: secondsUntilRefresh())
    }

    // Seconds until the next scheduled poll, read from the poll timer's own
    // fire date so it stays accurate regardless of when the menu opened.
    private func secondsUntilRefresh() -> Int? {
        guard let fireDate = pollTimer?.fireDate else { return nil }
        return max(0, Int(fireDate.timeIntervalSinceNow.rounded()))
    }

    // MARK: - Menu actions

    @objc func refreshNow(_ sender: NSMenuItem) {
        requestRefresh()
    }

    // Switches the active creature, persists the choice, and replays the
    // latest snapshot to every layer so the change shows immediately.
    @objc func selectCreature(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        creature = CreatureCatalog.creature(id: id)
        UserDefaults.standard.set(id, forKey: Self.creatureDefaultsKey)
        if let snapshot = lastSnapshot {
            fanOut(snapshot: snapshot)
        } else {
            // No snapshot yet (switch raced the very first poll): fetch one
            // now so every layer repaints with the new creature immediately.
            requestRefresh()
        }
    }

    // The pet counts as a real display only once its factory exists; without
    // one, disabling the menu bar would leave the app with zero UI.
    private var canDisableMenuBarDisplay: Bool {
        DisplayTogglePolicy.canDisable(displayFlags, .menuBar) && petLayerFactory != nil
    }

    @objc func toggleMenuBarDisplay(_ sender: NSMenuItem) {
        // Guarded here too: a stale menu could fire this action even while
        // the item is grayed out. Turning the menu bar ON is always allowed.
        guard !displayFlags.menuBar || canDisableMenuBarDisplay else { return }
        setDisplayFlags(DisplayTogglePolicy.toggling(displayFlags, .menuBar))
    }

    @objc func togglePetDisplay(_ sender: NSMenuItem) {
        setDisplayFlags(DisplayTogglePolicy.toggling(displayFlags, .pet))
    }

    // MARK: - Display flags

    // Missing keys mean true: both displays are ON by default for existing
    // users. bool(forKey:) defaults an absent key to false, so the flags are
    // probed via object(forKey:) instead.
    private static func loadDisplayFlags() -> DisplayFlags {
        let defaults = UserDefaults.standard
        return DisplayFlags(
            menuBar: (defaults.object(forKey: displayMenuBarEnabledKey) as? Bool) ?? true,
            pet: (defaults.object(forKey: displayPetEnabledKey) as? Bool) ?? true)
    }

    private func persistDisplayFlags() {
        let defaults = UserDefaults.standard
        defaults.set(displayFlags.menuBar, forKey: Self.displayMenuBarEnabledKey)
        defaults.set(displayFlags.pet, forKey: Self.displayPetEnabledKey)
    }

    private func setDisplayFlags(_ next: DisplayFlags) {
        guard next != displayFlags else { return }
        displayFlags = next
        persistDisplayFlags()
        syncMenuBarLayer()
        syncPetLayer()
        menuNeedsUpdate(statusMenu)
    }

    // Creates or destroys the status-item layer to match the flag. attach()
    // replays the latest snapshot, so a re-created layer renders immediately;
    // dropping the controller releases its NSStatusItem and the icon vanishes.
    private func syncMenuBarLayer() {
        if displayFlags.menuBar {
            guard statusItemController == nil else { return }
            let controller = StatusItemController(
                menu: statusMenu,
                initialCreature: creature,
                suspiciousSkipThreshold: config.suspiciousSkipThreshold)
            statusItemController = controller
            attach(controller)
        } else if let controller = statusItemController {
            detach(controller)
            statusItemController = nil
        }
    }

    // Makes togglePetDisplay live: assigning the factory applies the current
    // flag at once via didSet. The closure and its unavailable callback both
    // capture the engine weakly — engine -> factory -> engine would otherwise
    // be a retain cycle.
    private func registerPetLayerFactory() {
        let threshold = config.suspiciousSkipThreshold
        petLayerFactory = { [weak self] in
            PetWindowController(
                initialCreature: self?.currentCreature
                    ?? CreatureCatalog.creature(id: CreatureCatalog.defaultID),
                suspiciousSkipThreshold: threshold,
                menu: self?.menu ?? NSMenu(),
                onScreensUnavailable: { [weak self] in
                    self?.handlePetWindowUnavailable()
                })
        }
    }

    // The pet window could not show (no screens attached): flip the flags so
    // the pet turns off and the menu bar comes back — the app must never be
    // left with zero visible displays.
    private func handlePetWindowUnavailable() {
        // Deferred: show() can report unavailability synchronously from
        // inside syncPetLayer; mutating the flags mid-sync would re-enter it.
        DispatchQueue.main.async { [weak self] in
            self?.setDisplayFlags(DisplayFlags(menuBar: true, pet: false))
        }
    }

    // Same lifecycle for the pet layer; a nil factory means the flag only
    // persists and no layer exists.
    private func syncPetLayer() {
        if displayFlags.pet {
            guard petLayer == nil, let factory = petLayerFactory else { return }
            let layer = factory()
            petLayer = layer
            attach(layer)
            layer.show()
        } else if let layer = petLayer {
            layer.hide()
            detach(layer)
            petLayer = nil
        }
    }

    // The plist file state (loginItemManager.isEnabled) drives the checkbox,
    // so a rebuild right after toggling keeps the menu honest even if the
    // launchctl call itself failed.
    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        loginItemManager.toggle()
        menuNeedsUpdate(statusMenu)
    }

    // Per-model menu-bar tint. Kept visually in sync with the pet's own
    // PetPalette.accentColor(for:) (raw RGB in the AppKit-free pet module);
    // update both together when a model color changes.
    private static let accentColors: [ModelFamily: NSColor] = [
        .opus: .systemOrange,
        .sonnet: .systemBlue,
        .haiku: .systemGreen,
        .fable: .systemPurple
    ]
}

#endif
