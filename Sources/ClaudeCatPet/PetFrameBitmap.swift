// Cross-platform frame rasterizer: turns an ASCII pixel map into raw RGBA
// bytes so the platform layer only has to wrap them in a native image once.
public enum PetFrameBitmap {
    // Returns petGrid * petGrid * 4 bytes, row-major from the top-left
    // (matching the map row order). '@' takes the passed accent color,
    // '.' is fully transparent. Unknown characters also render transparent:
    // the validator rejects them before art ships, so this is a safety net,
    // not a supported feature.
    public static func rgba(frame: PetFrame, palette: PetPalette, accent: PetColor) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: petGrid * petGrid * 4)
        for (rowIndex, row) in frame.rows.prefix(petGrid).enumerated() {
            var offset = rowIndex * petGrid * 4
            for char in row.prefix(petGrid) {
                if let color = color(for: char, palette: palette, accent: accent) {
                    buffer[offset] = color.r
                    buffer[offset + 1] = color.g
                    buffer[offset + 2] = color.b
                    buffer[offset + 3] = color.a
                }
                offset += 4
            }
        }
        return buffer
    }

    private static func color(for char: Character,
                              palette: PetPalette,
                              accent: PetColor) -> PetColor? {
        if char == "." { return nil }
        if char == "@" { return accent }
        return palette.colors[char]
    }
}
