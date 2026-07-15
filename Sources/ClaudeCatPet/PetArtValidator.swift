// Structural validation for creature art; the Python art generator
// mirrors these rules, and the catalog test enforces them on Linux CI.
public enum PetArtValidator {
    private static let expectedStageCount = 6
    private static let minAnimationFrames = 2

    // Returns human-readable issue strings; an empty array means valid.
    public static func issues(in art: PetCreatureArt, palette: PetPalette) -> [String] {
        var issues: [String] = []
        // '.' and '@' carry fixed meanings (transparent, accent); a palette
        // entry for them would silently shadow that contract.
        for reserved: Character in [".", "@"] where palette.colors[reserved] != nil {
            issues.append("palette: reserved character '\(reserved)' must not be defined in colors")
        }
        if art.stages.count != expectedStageCount {
            issues.append("\(art.id): expected \(expectedStageCount) stages, found \(art.stages.count)")
        }
        for (stageIndex, stage) in art.stages.enumerated() {
            let location = "stage \(stageIndex)"
            if stage.jump.count < minAnimationFrames {
                issues.append("\(art.id) \(location): jump needs at least \(minAnimationFrames) frames, found \(stage.jump.count)")
            }
            if stage.sleep.count < minAnimationFrames {
                issues.append("\(art.id) \(location): sleep needs at least \(minAnimationFrames) frames, found \(stage.sleep.count)")
            }
            for (frameIndex, frame) in stage.jump.enumerated() {
                issues += frameIssues(frame, creature: art.id, location: "\(location) jump frame \(frameIndex)",
                                      palette: palette, requiresAccent: true)
            }
            for (frameIndex, frame) in stage.sleep.enumerated() {
                issues += frameIssues(frame, creature: art.id, location: "\(location) sleep frame \(frameIndex)",
                                      palette: palette, requiresAccent: true)
            }
            issues += frameIssues(stage.drag, creature: art.id, location: "\(location) drag frame",
                                  palette: palette, requiresAccent: true)
            issues += frameIssues(stage.hover, creature: art.id, location: "\(location) hover frame",
                                  palette: palette, requiresAccent: true)
        }
        if art.broken.isEmpty {
            issues.append("\(art.id): broken needs at least 1 frame, found 0")
        }
        // Broken frames are exempt from the accent rule: a broken pet
        // deliberately shows no model-family color.
        for (frameIndex, frame) in art.broken.enumerated() {
            issues += frameIssues(frame, creature: art.id, location: "broken frame \(frameIndex)",
                                  palette: palette, requiresAccent: false)
        }
        return issues
    }

    private static func frameIssues(_ frame: PetFrame, creature: String, location: String,
                                    palette: PetPalette, requiresAccent: Bool) -> [String] {
        var issues: [String] = []
        if frame.rows.count != petGrid {
            issues.append("\(creature) \(location): expected \(petGrid) rows, found \(frame.rows.count)")
        }
        var hasVisiblePixel = false
        var hasAccent = false
        for (rowIndex, row) in frame.rows.enumerated() {
            if row.count != petGrid {
                issues.append("\(creature) \(location) row \(rowIndex): expected \(petGrid) chars, found \(row.count)")
            }
            var unknownInRow: Set<Character> = []
            for character in row {
                if character == "." { continue }
                hasVisiblePixel = true
                if character == "@" {
                    hasAccent = true
                } else if palette.colors[character] == nil {
                    unknownInRow.insert(character)
                }
            }
            for character in unknownInRow.sorted() {
                issues.append("\(creature) \(location) row \(rowIndex): character '\(character)' not in palette")
            }
        }
        if !hasVisiblePixel {
            issues.append("\(creature) \(location): empty frame, no non-transparent pixels")
        }
        if requiresAccent && !hasAccent {
            issues.append("\(creature) \(location): missing '@' accent pixel")
        }
        return issues
    }
}
