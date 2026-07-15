import XCTest
import ClaudeCatPet

final class PetFrameBitmapTests: XCTestCase {
    private let palette = PetPalette(colors: [
        "#": PetColor(r: 10, g: 20, b: 30, a: 255),
        "o": PetColor(r: 200, g: 100, b: 50, a: 128)
    ])
    private let accent = PetColor(r: 230, g: 126, b: 34, a: 255)

    private func transparentRows() -> [String] {
        Array(repeating: String(repeating: ".", count: petGrid), count: petGrid)
    }

    // Builds a frame that is transparent except for single characters
    // placed at explicit (row, column) positions.
    private func frame(with pixels: [(row: Int, col: Int, char: Character)]) -> PetFrame {
        var rows = transparentRows()
        for pixel in pixels {
            var chars = Array(rows[pixel.row])
            chars[pixel.col] = pixel.char
            rows[pixel.row] = String(chars)
        }
        return PetFrame(rows: rows)
    }

    private func bytes(in buffer: [UInt8], row: Int, col: Int) -> [UInt8] {
        let offset = (row * petGrid + col) * 4
        return Array(buffer[offset..<(offset + 4)])
    }

    func testOutputByteCountIsExactly64x64x4() {
        let buffer = PetFrameBitmap.rgba(frame: frame(with: []),
                                         palette: palette,
                                         accent: accent)
        XCTAssertEqual(buffer.count, petGrid * petGrid * 4)
    }

    func testPaletteCharacterLandsAtRowMajorOffset() {
        let buffer = PetFrameBitmap.rgba(frame: frame(with: [(row: 5, col: 12, char: "#"),
                                                             (row: 63, col: 63, char: "o")]),
                                         palette: palette,
                                         accent: accent)
        XCTAssertEqual(bytes(in: buffer, row: 5, col: 12), [10, 20, 30, 255])
        XCTAssertEqual(bytes(in: buffer, row: 63, col: 63), [200, 100, 50, 128])
    }

    func testAccentPlaceholderTakesPassedAccentColor() {
        let art = frame(with: [(row: 7, col: 3, char: "@")])
        let first = PetFrameBitmap.rgba(frame: art, palette: palette, accent: accent)
        XCTAssertEqual(bytes(in: first, row: 7, col: 3), [230, 126, 34, 255])

        let otherAccent = PetColor(r: 52, g: 120, b: 246, a: 255)
        let second = PetFrameBitmap.rgba(frame: art, palette: palette, accent: otherAccent)
        XCTAssertEqual(bytes(in: second, row: 7, col: 3), [52, 120, 246, 255])
        XCTAssertNotEqual(bytes(in: first, row: 7, col: 3),
                          bytes(in: second, row: 7, col: 3))
    }

    func testTransparentDotMapsToAllZeroBytes() {
        let buffer = PetFrameBitmap.rgba(frame: frame(with: []),
                                         palette: palette,
                                         accent: accent)
        XCTAssertEqual(bytes(in: buffer, row: 0, col: 0), [0, 0, 0, 0])
        XCTAssertEqual(bytes(in: buffer, row: 32, col: 32), [0, 0, 0, 0])
    }

    func testUnknownCharacterRendersTransparent() {
        let buffer = PetFrameBitmap.rgba(frame: frame(with: [(row: 1, col: 1, char: "Z")]),
                                         palette: palette,
                                         accent: accent)
        XCTAssertEqual(bytes(in: buffer, row: 1, col: 1), [0, 0, 0, 0])
    }
}
