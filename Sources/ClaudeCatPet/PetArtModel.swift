// Data model for the 64x64 full-color pixel art of desktop pet creatures.
// Frames are ASCII pixel maps: '.' is transparent, '@' is the model-family
// accent placeholder, every other character resolves through a PetPalette.

// Side length of the square pixel grid every pet frame must fill.
public let petGrid = 64

public struct PetFrame: Equatable {
    public let rows: [String]

    public init(rows: [String]) {
        self.rows = rows
    }
}

// Animation frames for one growth stage; the click reaction reuses
// the jump frames, so there is no dedicated click art.
public struct PetStageSprites {
    public let jump: [PetFrame]
    public let sleep: [PetFrame]
    public let drag: PetFrame
    public let hover: PetFrame

    public init(jump: [PetFrame], sleep: [PetFrame], drag: PetFrame, hover: PetFrame) {
        self.jump = jump
        self.sleep = sleep
        self.drag = drag
        self.hover = hover
    }
}

public struct PetCreatureArt {
    public let id: String
    public let displayName: String
    public let stages: [PetStageSprites]
    public let broken: [PetFrame]

    public init(id: String, displayName: String, stages: [PetStageSprites], broken: [PetFrame]) {
        self.id = id
        self.displayName = displayName
        self.stages = stages
        self.broken = broken
    }

    // Stage is clamped so an out-of-bounds value never crashes. Empty
    // stages are a validator error; failing fast here beats an
    // out-of-bounds crash with no message.
    public func stageSprites(stage: Int) -> PetStageSprites {
        precondition(!stages.isEmpty, "PetCreatureArt '\(id)' has no stages")
        let clamped = min(max(stage, 0), stages.count - 1)
        return stages[clamped]
    }
}
