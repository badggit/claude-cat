// Pure display-toggle rules for the menu-bar/pet display pair.
// Invariant: at least one display stays enabled at all times.
// Persistence and menu wiring live in the app layer, not here.

public struct DisplayFlags: Equatable {
    public var menuBar: Bool
    public var pet: Bool

    public static let bothOn = DisplayFlags(menuBar: true, pet: true)

    public init(menuBar: Bool, pet: Bool) {
        self.menuBar = menuBar
        self.pet = pet
    }
}

public enum PetDisplay {
    case menuBar
    case pet
}

public enum DisplayTogglePolicy {
    // Flips the named flag; a flip that would leave both displays
    // disabled is rejected and returns the input unchanged.
    public static func toggling(_ flags: DisplayFlags, _ display: PetDisplay) -> DisplayFlags {
        var next = flags
        switch display {
        case .menuBar:
            next.menuBar.toggle()
        case .pet:
            next.pet.toggle()
        }
        guard next.menuBar || next.pet else { return flags }
        return next
    }

    // False exactly when the named display is the last enabled one;
    // drives the grayed-out state of the corresponding menu item.
    public static func canDisable(_ flags: DisplayFlags, _ display: PetDisplay) -> Bool {
        switch display {
        case .menuBar:
            return flags.pet
        case .pet:
            return flags.menuBar
        }
    }

    // Repairs persisted both-off corruption by forcing the menu bar on;
    // every legal combination passes through untouched.
    public static func sanitized(_ flags: DisplayFlags) -> DisplayFlags {
        guard !flags.menuBar && !flags.pet else { return flags }
        return DisplayFlags(menuBar: true, pet: false)
    }
}
