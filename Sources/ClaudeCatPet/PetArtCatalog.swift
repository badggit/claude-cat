// Registry of generated pixel art; illustrated visuals are described by
// PetVisualCatalog and do not expose palette-map frames.
public enum PetArtCatalog {
    public static let all: [PetCreatureArt] = [.bunny, .bird, .flower, .pig]

    public static let validationPalette = PetPalette.standard

    public static func creature(id: String) -> PetCreatureArt? {
        all.first { $0.id == id }
    }
}
