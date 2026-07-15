public enum PetVisualKind: Equatable {
    case illustratedCat
    case pixelArt
}

public struct PetVisualDescriptor: Equatable {
    public let id: String
    public let displayName: String
    public let stageCount: Int
    public let kind: PetVisualKind

    public init(id: String, displayName: String, stageCount: Int, kind: PetVisualKind) {
        self.id = id
        self.displayName = displayName
        self.stageCount = stageCount
        self.kind = kind
    }
}

public enum PetVisualCatalog {
    public static let all = [
        PetVisualDescriptor(id: "cat", displayName: "Cat", stageCount: 6, kind: .illustratedCat),
        PetVisualDescriptor(id: "bunny", displayName: "Bunny", stageCount: 6, kind: .pixelArt),
        PetVisualDescriptor(id: "bird", displayName: "Bird", stageCount: 6, kind: .pixelArt),
        PetVisualDescriptor(id: "flower", displayName: "Flower", stageCount: 6, kind: .pixelArt),
        PetVisualDescriptor(id: "pig", displayName: "Pig", stageCount: 6, kind: .pixelArt)
    ]

    public static func visual(id: String) -> PetVisualDescriptor? {
        all.first { $0.id == id }
    }

    public static func stageCount(for id: String) -> Int? {
        visual(id: id)?.stageCount
    }
}
